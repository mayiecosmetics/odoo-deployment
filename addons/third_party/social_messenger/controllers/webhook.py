# -*- coding: utf-8 -*-
import hashlib
import hmac
import json
import logging

from odoo import http, SUPERUSER_ID
from odoo.http import request, Response

_logger = logging.getLogger(__name__)


class SocialMessengerWebhook(http.Controller):
    """
    Webhook endpoints for Meta (Facebook Messenger & Instagram).
    
    Configure in Meta Developer Console:
        Callback URL:  https://your-odoo-domain/social_messenger/webhook/<account_id>
        Verify Token:  (the token you set on the social.account record)
        Subscriptions: messages, messaging_postbacks
    """

    # -----------------------------------------------------------------
    # Webhook Verification  (GET)
    # -----------------------------------------------------------------
    @http.route(
        '/social_messenger/webhook/<int:account_id>',
        type='http', auth='none', methods=['GET'], csrf=False,
    )
    def webhook_verify(self, account_id, **kwargs):
        """
        Meta sends a GET request with hub.mode, hub.verify_token and
        hub.challenge to verify the webhook URL.
        """
        mode = kwargs.get('hub.mode')
        token = kwargs.get('hub.verify_token')
        challenge = kwargs.get('hub.challenge')

        if not all([mode, token, challenge]):
            return Response('Missing parameters', status=400)

        env = request.env(user=SUPERUSER_ID)
        account = env['social.account'].browse(account_id).exists()
        if not account:
            _logger.warning("Webhook verify: account %s not found", account_id)
            return Response('Account not found', status=404)

        if mode == 'subscribe' and token == account.verify_token:
            _logger.info("Webhook verified for account %s", account_id)
            return Response(challenge, status=200)

        _logger.warning("Webhook verification failed for account %s", account_id)
        return Response('Verification failed', status=403)

    # -----------------------------------------------------------------
    # Incoming Messages  (POST)
    # -----------------------------------------------------------------
    @http.route(
        '/social_messenger/webhook/<int:account_id>',
        type='http', auth='none', methods=['POST'], csrf=False,
    )
    def webhook_receive(self, account_id, **kwargs):
        """
        Receive incoming webhook events from Meta.
        Supports both Messenger and Instagram messaging events.
        """
        try:
            raw_body = request.httprequest.get_data(as_text=True)
            data = json.loads(raw_body)
        except (json.JSONDecodeError, Exception) as e:
            _logger.error("Invalid webhook payload: %s", e)
            return Response('Invalid payload', status=400)

        env = request.env(user=SUPERUSER_ID)
        account = env['social.account'].browse(account_id).exists()
        if not account:
            _logger.warning("Webhook: account %s not found", account_id)
            return Response('Account not found', status=404)

        # Optional: verify request signature
        self._verify_signature(account, raw_body)

        # Determine platform from the webhook object type
        obj_type = data.get('object', '')
        # "page" = Messenger, "instagram" = Instagram
        _logger.info(
            "Webhook event received for account %s, object=%s",
            account_id, obj_type,
        )

        entries = data.get('entry', [])
        for entry in entries:
            messaging_events = entry.get('messaging', [])
            for event in messaging_events:
                self._process_messaging_event(env, account, event)

        # Meta requires a 200 response quickly
        return Response('EVENT_RECEIVED', status=200)

    # -----------------------------------------------------------------
    # Process individual messaging events
    # -----------------------------------------------------------------
    def _process_messaging_event(self, env, account, event):
        """Parse a single messaging event and create/update conversation."""
        sender_id = event.get('sender', {}).get('id', '')
        recipient_id = event.get('recipient', {}).get('id', '')
        timestamp = event.get('timestamp')

        # Skip messages sent by the page itself (echo)
        message_data = event.get('message', {})
        if message_data.get('is_echo'):
            _logger.debug("Skipping echo message")
            return

        if not sender_id:
            _logger.warning("No sender_id in messaging event")
            return

        # Extract message content
        text = message_data.get('text', '')
        mid = message_data.get('mid', '')

        # Handle attachments
        attachment_url = ''
        attachments = message_data.get('attachments', [])
        if attachments:
            payload = attachments[0].get('payload', {})
            attachment_url = payload.get('url', '')

        # Find or create conversation
        conversation = self._get_or_create_conversation(
            env, account, sender_id,
        )

        # Add the incoming message
        conversation._add_incoming_message(
            text=text,
            mid=mid,
            timestamp=timestamp,
            attachment_url=attachment_url,
        )

        _logger.info(
            "Incoming message from %s on account %s: %s",
            sender_id, account.id, (text or '[attachment]')[:50],
        )

    def _get_or_create_conversation(self, env, account, sender_id):
        """Find existing conversation or create a new one."""
        Conversation = env['social.conversation'].sudo()
        conv = Conversation.search([
            ('account_id', '=', account.id),
            ('sender_id', '=', sender_id),
        ], limit=1)

        if conv:
            return conv

        # Fetch profile info
        profile = account._get_user_profile(sender_id)
        sender_name = profile.get('name', '')
        profile_pic = profile.get('profile_pic', '')

        # Try to match existing partner
        partner = None
        if sender_name:
            partner = env['res.partner'].sudo().search([
                ('social_sender_id', '=', sender_id),
            ], limit=1)

        vals = {
            'account_id': account.id,
            'sender_id': sender_id,
            'sender_name': sender_name or f'User {sender_id}',
            'sender_profile_pic': profile_pic,
            'partner_id': partner.id if partner else False,
        }
        conv = Conversation.create(vals)
        _logger.info(
            "Created new conversation %s for sender %s",
            conv.id, sender_id,
        )
        return conv

    def _verify_signature(self, account, raw_body):
        """
        Optionally verify the X-Hub-Signature-256 header.
        Non-blocking: logs a warning if invalid but does not reject.
        """
        signature_header = request.httprequest.headers.get('X-Hub-Signature-256', '')
        if not signature_header or not account.app_secret:
            return

        try:
            expected = 'sha256=' + hmac.new(
                account.app_secret.encode('utf-8'),
                raw_body.encode('utf-8'),
                hashlib.sha256,
            ).hexdigest()
            if not hmac.compare_digest(signature_header, expected):
                _logger.warning(
                    "Webhook signature mismatch for account %s", account.id,
                )
        except Exception as e:
            _logger.warning("Signature verification error: %s", e)

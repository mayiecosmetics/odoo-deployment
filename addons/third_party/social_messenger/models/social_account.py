# -*- coding: utf-8 -*-
import json
import logging
import requests

from odoo import api, fields, models, _
from odoo.exceptions import UserError, ValidationError

_logger = logging.getLogger(__name__)

META_GRAPH_API_URL = "https://graph.facebook.com/v21.0"


class SocialAccount(models.Model):
    _name = 'social.account'
    _description = 'Social Media Account (Facebook / Instagram)'
    _inherit = ['mail.thread']

    name = fields.Char(string='Account Name', required=True, tracking=True)
    platform = fields.Selection([
        ('facebook', 'Facebook Messenger'),
        ('instagram', 'Instagram'),
    ], string='Platform', required=True, default='facebook', tracking=True)
    state = fields.Selection([
        ('draft', 'Not Connected'),
        ('connected', 'Connected'),
        ('error', 'Error'),
    ], string='Status', default='draft', tracking=True)

    # Meta App Credentials
    app_id = fields.Char(string='Meta App ID', required=True)
    app_secret = fields.Char(string='Meta App Secret', required=True)
    verify_token = fields.Char(
        string='Webhook Verify Token', required=True,
        help='A random secret string you choose. Must match what you enter in '
             'Meta Developer Console when subscribing the webhook.',
    )

    # Page / Account tokens
    page_access_token = fields.Char(
        string='Page Access Token',
        help='Long-lived Page Access Token generated from Meta Developer Console.',
    )
    page_id = fields.Char(string='Facebook Page ID')
    instagram_account_id = fields.Char(
        string='Instagram Business Account ID',
        help='The Instagram Business Account ID linked to your Facebook Page.',
    )

    # Webhook URL (informational)
    webhook_url = fields.Char(
        string='Webhook URL', compute='_compute_webhook_url', store=False,
        help='Configure this URL in your Meta Developer Console → Webhooks.',
    )

    conversation_ids = fields.One2many(
        'social.conversation', 'account_id', string='Conversations',
    )
    conversation_count = fields.Integer(
        compute='_compute_conversation_count', string='Conversations',
    )

    company_id = fields.Many2one(
        'res.company', string='Company',
        default=lambda self: self.env.company, required=True,
    )

    # -------------------------------------------------------------------------
    # Computed
    # -------------------------------------------------------------------------
    @api.depends('platform')
    def _compute_webhook_url(self):
        base_url = self.env['ir.config_parameter'].sudo().get_param('web.base.url')
        for rec in self:
            rec.webhook_url = f"{base_url}/social_messenger/webhook/{rec.id}" if rec.id else ''

    def _compute_conversation_count(self):
        for rec in self:
            rec.conversation_count = self.env['social.conversation'].search_count(
                [('account_id', '=', rec.id)]
            )

    # -------------------------------------------------------------------------
    # Actions
    # -------------------------------------------------------------------------
    def action_test_connection(self):
        """Verify the page access token works by calling /me on Graph API."""
        self.ensure_one()
        if not self.page_access_token:
            raise UserError(_("Please enter a Page Access Token first."))

        url = f"{META_GRAPH_API_URL}/me"
        params = {'access_token': self.page_access_token}
        try:
            resp = requests.get(url, params=params, timeout=15)
            data = resp.json()
        except Exception as e:
            self.state = 'error'
            raise UserError(_("Connection failed: %s") % str(e))

        if 'error' in data:
            self.state = 'error'
            raise UserError(
                _("Meta API Error: %s") % data['error'].get('message', 'Unknown')
            )

        # Update page info
        self.page_id = data.get('id', '')
        if not self.name or self.name == _('New'):
            self.name = data.get('name', self.name)
        self.state = 'connected'

        # If Instagram, also fetch IG account ID
        if self.platform == 'instagram':
            self._fetch_instagram_account_id()

        return {
            'type': 'ir.actions.client',
            'tag': 'display_notification',
            'params': {
                'title': _('Success'),
                'message': _('Connected to: %s (ID: %s)') % (data.get('name'), data.get('id')),
                'type': 'success',
                'sticky': False,
            },
        }

    def _fetch_instagram_account_id(self):
        """Fetch the Instagram Business Account ID linked to the FB Page."""
        self.ensure_one()
        url = f"{META_GRAPH_API_URL}/{self.page_id}"
        params = {
            'fields': 'instagram_business_account',
            'access_token': self.page_access_token,
        }
        try:
            resp = requests.get(url, params=params, timeout=15)
            data = resp.json()
            ig_data = data.get('instagram_business_account', {})
            self.instagram_account_id = ig_data.get('id', '')
        except Exception as e:
            _logger.warning("Failed to fetch Instagram account ID: %s", e)

    def action_view_conversations(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': _('Conversations'),
            'res_model': 'social.conversation',
            'view_mode': 'list,form',
            'domain': [('account_id', '=', self.id)],
            'context': {'default_account_id': self.id},
        }

    # -------------------------------------------------------------------------
    # Meta Graph API Helpers
    # -------------------------------------------------------------------------
    def _send_message(self, recipient_id, message_text, attachment_url=None):
        """Send a message via Meta Send API (works for both Messenger & IG)."""
        self.ensure_one()
        url = f"{META_GRAPH_API_URL}/{self.page_id}/messages"
        headers = {'Content-Type': 'application/json'}
        params = {'access_token': self.page_access_token}

        payload = {
            'recipient': {'id': recipient_id},
        }

        if attachment_url:
            payload['message'] = {
                'attachment': {
                    'type': 'image',
                    'payload': {'url': attachment_url, 'is_reusable': True},
                }
            }
        else:
            payload['message'] = {'text': message_text}

        try:
            resp = requests.post(
                url, headers=headers, params=params,
                data=json.dumps(payload), timeout=30,
            )
            data = resp.json()
            if 'error' in data:
                _logger.error("Meta Send API error: %s", data['error'])
                raise UserError(
                    _("Failed to send message: %s") % data['error'].get('message', '')
                )
            return data
        except requests.exceptions.RequestException as e:
            _logger.error("Network error sending message: %s", e)
            raise UserError(_("Network error: %s") % str(e))

    def _get_user_profile(self, user_id):
        """Fetch a user's profile (name, profile_pic) from Meta Graph API."""
        self.ensure_one()
        url = f"{META_GRAPH_API_URL}/{user_id}"
        params = {
            'fields': 'name,profile_pic',
            'access_token': self.page_access_token,
        }
        try:
            resp = requests.get(url, params=params, timeout=15)
            data = resp.json()
            if 'error' not in data:
                return data
        except Exception as e:
            _logger.warning("Could not fetch profile for %s: %s", user_id, e)
        return {}

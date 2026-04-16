# -*- coding: utf-8 -*-
import logging

from odoo import fields, models, _
from odoo.exceptions import UserError

_logger = logging.getLogger(__name__)


class SocialMessageReplyWizard(models.TransientModel):
    _name = 'social.message.reply.wizard'
    _description = 'Reply to Social Conversation'

    conversation_id = fields.Many2one(
        'social.conversation', string='Conversation',
        required=True, ondelete='cascade',
    )
    body = fields.Text(string='Message', required=True)

    def action_send(self):
        """Send the reply via Meta Send API and record it."""
        self.ensure_one()
        conv = self.conversation_id
        account = conv.account_id

        if account.state != 'connected':
            raise UserError(_("The social account is not connected. Please test the connection first."))
        if not self.body.strip():
            raise UserError(_("Message cannot be empty."))

        # Send via Meta API
        result = account._send_message(
            recipient_id=conv.sender_id,
            message_text=self.body.strip(),
        )

        # Record the outgoing message
        meta_mid = result.get('message_id', '')
        conv._add_outgoing_message(
            text=self.body.strip(),
            meta_message_id=meta_mid,
        )

        return {
            'type': 'ir.actions.client',
            'tag': 'display_notification',
            'params': {
                'title': _('Message Sent'),
                'message': _('Your reply has been sent successfully.'),
                'type': 'success',
                'sticky': False,
            },
        }

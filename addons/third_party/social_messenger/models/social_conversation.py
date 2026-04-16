# -*- coding: utf-8 -*-
import logging

from odoo import api, fields, models, _

_logger = logging.getLogger(__name__)


class SocialConversation(models.Model):
    _name = 'social.conversation'
    _description = 'Social Messenger Conversation'
    _inherit = ['mail.thread']
    _order = 'last_message_date desc'

    name = fields.Char(string='Conversation', compute='_compute_name', store=True)
    account_id = fields.Many2one(
        'social.account', string='Social Account',
        required=True, ondelete='cascade',
    )
    platform = fields.Selection(related='account_id.platform', store=True)
    partner_id = fields.Many2one('res.partner', string='Contact', tracking=True)

    # The platform-specific sender ID (PSID for Messenger, IGSID for Instagram)
    sender_id = fields.Char(
        string='Sender ID', required=True, index=True,
        help='Platform-Scoped User ID of the person messaging your page.',
    )
    sender_name = fields.Char(string='Sender Name')
    sender_profile_pic = fields.Char(string='Profile Picture URL')

    message_ids = fields.One2many(
        'social.message', 'conversation_id', string='Messages',
    )
    message_count = fields.Integer(
        compute='_compute_message_count', string='Messages',
    )
    last_message_date = fields.Datetime(string='Last Message', index=True)
    last_message_preview = fields.Char(string='Last Message Preview')

    state = fields.Selection([
        ('active', 'Active'),
        ('archived', 'Archived'),
    ], default='active', string='Status')

    company_id = fields.Many2one(
        related='account_id.company_id', store=True,
    )

    _sql_constraints = [
        (
            'unique_sender_per_account',
            'UNIQUE(account_id, sender_id)',
            'A conversation with this sender already exists for this account.',
        ),
    ]

    # -------------------------------------------------------------------------
    # Computed
    # -------------------------------------------------------------------------
    @api.depends('sender_name', 'partner_id', 'platform')
    def _compute_name(self):
        for rec in self:
            label = rec.partner_id.name or rec.sender_name or rec.sender_id or _('Unknown')
            platform_label = dict(rec._fields['platform'].selection).get(rec.platform, '')
            rec.name = f"{label} ({platform_label})" if platform_label else label

    def _compute_message_count(self):
        for rec in self:
            rec.message_count = self.env['social.message'].search_count(
                [('conversation_id', '=', rec.id)]
            )

    # -------------------------------------------------------------------------
    # Business Logic
    # -------------------------------------------------------------------------
    def action_send_message(self):
        """Open the reply wizard."""
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': _('Reply'),
            'res_model': 'social.message.reply.wizard',
            'view_mode': 'form',
            'target': 'new',
            'context': {
                'default_conversation_id': self.id,
            },
        }

    def action_create_partner(self):
        """Create a res.partner from the sender profile."""
        self.ensure_one()
        if self.partner_id:
            raise models.ValidationError(_("A contact is already linked."))
        partner = self.env['res.partner'].create({
            'name': self.sender_name or f"Social User {self.sender_id}",
            'social_sender_id': self.sender_id,
            'social_platform': self.platform,
            'image_1920': False,  # Could fetch from profile_pic URL
        })
        self.partner_id = partner.id
        return {
            'type': 'ir.actions.client',
            'tag': 'display_notification',
            'params': {
                'title': _('Contact Created'),
                'message': _('Contact "%s" has been created and linked.') % partner.name,
                'type': 'success',
                'sticky': False,
            },
        }

    def action_view_messages(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': _('Messages'),
            'res_model': 'social.message',
            'view_mode': 'list,form',
            'domain': [('conversation_id', '=', self.id)],
        }

    def _add_incoming_message(self, text, mid=None, timestamp=None, attachment_url=None):
        """Create an incoming message record and post to chatter."""
        self.ensure_one()
        vals = {
            'conversation_id': self.id,
            'direction': 'incoming',
            'body': text or '',
            'meta_message_id': mid or '',
            'attachment_url': attachment_url or '',
            'message_date': fields.Datetime.now(),
        }
        msg = self.env['social.message'].sudo().create(vals)

        # Update conversation
        self.sudo().write({
            'last_message_date': fields.Datetime.now(),
            'last_message_preview': (text or '[attachment]')[:100],
        })

        # Post to chatter so it appears in Discuss
        body_html = text or ''
        if attachment_url:
            body_html += f'<br/><a href="{attachment_url}" target="_blank">[Attachment]</a>'

        platform_label = 'Facebook Messenger' if self.platform == 'facebook' else 'Instagram'
        self.message_post(
            body=f"<b>[{platform_label} – Incoming]</b><br/>{body_html}",
            message_type='comment',
            subtype_xmlid='mail.mt_comment',
            author_id=self.partner_id.id if self.partner_id else None,
        )
        return msg

    def _add_outgoing_message(self, text, meta_message_id=None):
        """Record an outgoing (reply) message."""
        self.ensure_one()
        vals = {
            'conversation_id': self.id,
            'direction': 'outgoing',
            'body': text or '',
            'meta_message_id': meta_message_id or '',
            'message_date': fields.Datetime.now(),
        }
        msg = self.env['social.message'].sudo().create(vals)

        self.sudo().write({
            'last_message_date': fields.Datetime.now(),
            'last_message_preview': (text or '')[:100],
        })

        platform_label = 'Facebook Messenger' if self.platform == 'facebook' else 'Instagram'
        self.message_post(
            body=f"<b>[{platform_label} – Sent]</b><br/>{text}",
            message_type='comment',
            subtype_xmlid='mail.mt_comment',
        )
        return msg

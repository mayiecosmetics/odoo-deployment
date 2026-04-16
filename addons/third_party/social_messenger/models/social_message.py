# -*- coding: utf-8 -*-
from odoo import fields, models


class SocialMessage(models.Model):
    _name = 'social.message'
    _description = 'Social Messenger Message'
    _order = 'message_date desc'

    conversation_id = fields.Many2one(
        'social.conversation', string='Conversation',
        required=True, ondelete='cascade', index=True,
    )
    direction = fields.Selection([
        ('incoming', 'Incoming'),
        ('outgoing', 'Outgoing'),
    ], string='Direction', required=True)
    body = fields.Text(string='Message Body')
    attachment_url = fields.Char(string='Attachment URL')
    meta_message_id = fields.Char(string='Meta Message ID', index=True)
    message_date = fields.Datetime(
        string='Date', default=fields.Datetime.now, index=True,
    )

    account_id = fields.Many2one(
        related='conversation_id.account_id', store=True,
    )
    platform = fields.Selection(
        related='conversation_id.platform', store=True,
    )
    partner_id = fields.Many2one(
        related='conversation_id.partner_id', store=True,
    )

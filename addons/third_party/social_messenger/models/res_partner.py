# -*- coding: utf-8 -*-
from odoo import fields, models


class ResPartner(models.Model):
    _inherit = 'res.partner'

    social_sender_id = fields.Char(
        string='Social Sender ID',
        help='Platform-Scoped User ID from Facebook Messenger or Instagram.',
    )
    social_platform = fields.Selection([
        ('facebook', 'Facebook Messenger'),
        ('instagram', 'Instagram'),
    ], string='Social Platform')
    social_conversation_ids = fields.One2many(
        'social.conversation', 'partner_id',
        string='Social Conversations',
    )
    social_conversation_count = fields.Integer(
        compute='_compute_social_conversation_count',
        string='Social Conversations',
    )

    def _compute_social_conversation_count(self):
        for rec in self:
            rec.social_conversation_count = self.env['social.conversation'].search_count(
                [('partner_id', '=', rec.id)]
            )

    def action_view_social_conversations(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': 'Social Conversations',
            'res_model': 'social.conversation',
            'view_mode': 'list,form',
            'domain': [('partner_id', '=', self.id)],
        }

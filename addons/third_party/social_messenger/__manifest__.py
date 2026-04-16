# -*- coding: utf-8 -*-
{
    'name': 'Social Messenger',
    'version': '19.0.1.0.0',
    'category': 'Discuss',
    'summary': 'Facebook Messenger & Instagram DM in Odoo Discuss',
    'description': """
Social Messenger Integration
=============================

Bidirectional Facebook Messenger and Instagram Direct Message integration
with Odoo Discuss / Chatter.

Features
--------
* Receive Facebook Messenger messages in real-time via webhooks
* Receive Instagram Direct Messages in real-time via webhooks
* Reply to customers directly from the Odoo conversation form
* Every message logged in Odoo chatter (visible in Discuss)
* Automatic contact creation from social media profiles
* Link conversations to existing Odoo contacts (res.partner)
* Support for text messages and image attachments
* Multi-page / multi-account support
* Webhook signature verification (X-Hub-Signature-256)
* Security groups: User and Manager roles

Requirements
------------
* A Meta Developer App (free at developers.facebook.com)
* A Facebook Page linked to the Meta App
* Instagram Business/Creator account connected to your Facebook Page
* A publicly accessible Odoo instance with HTTPS

This module uses the Meta Graph API v21.0.
No external Python dependencies required beyond Odoo's standard libraries.
    """,
    'author': 'Adem Chedhly',
    'website': 'https://github.com/Adem-Chedhly/odoo-social-messenger',
    'license': 'LGPL-3',
    'depends': [
        'base',
        'mail',
        'contacts',
    ],
    'data': [
        'security/security.xml',
        'security/ir.model.access.csv',
        'data/ir_cron.xml',
        'views/social_account_views.xml',
        'views/social_conversation_views.xml',
        'views/res_partner_views.xml',
        'views/menu.xml',
    ],
    'images': [
        'static/description/banner.png',
    ],
    'assets': {},
    'installable': True,
    'application': True,
    'auto_install': False,
    # Uncomment below to make it a paid module:
    # 'price': 49.99,
    # 'currency': 'EUR',
}

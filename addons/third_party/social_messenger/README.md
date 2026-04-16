# Social Messenger Integration for Odoo 19

Bidirectional Facebook Messenger & Instagram DM integration with Odoo Discuss/Chatter.

## Features

- **Real-time incoming messages** via Meta Webhooks (no polling)
- **Reply from Odoo** — send messages back through the conversation form or chatter
- **Automatic contact matching** — links social senders to existing `res.partner` records
- **One-click contact creation** from unknown senders
- **Full history** — every message logged in both custom model and Odoo chatter
- **Multi-account** — connect multiple Facebook Pages and Instagram accounts
- **Webhook signature verification** for security
- **Supports text + image attachments** in both directions

## Requirements

- Odoo 19 (Community or Enterprise)
- Python 3.12+
- A public **HTTPS** URL for your Odoo instance (Meta requires HTTPS for webhooks)
- A **Meta Developer App** — free at [developers.facebook.com](https://developers.facebook.com)

## Installation

1. Copy the `social_messenger` folder into your Odoo addons path
2. Restart the Odoo server
3. Go to **Apps** → **Update Apps List**
4. Search for "Social Messenger" and click **Install**

## Setup — Step by Step

### 1. Create a Meta Developer App

1. Go to [developers.facebook.com](https://developers.facebook.com) → **My Apps** → **Create App**
2. Choose **"Other"** use case → **"Business"** app type
3. Name your app and create it

### 2. Add Products to Your App

1. In your app dashboard, click **+ Add Product**
2. Add **Messenger** (for Facebook Messenger integration)
3. Add **Instagram** (for Instagram DM integration)

### 3. Configure Messenger Settings

1. Go to **Messenger** → **Settings** in your app dashboard
2. Under **Access Tokens**, click **Add or Remove Pages** and select your Facebook Page
3. Click **Generate Token** for your page — **copy and save this token**
4. You need these permissions approved (for Development mode, they work automatically):
   - `pages_messaging`
   - `pages_manage_metadata`
   - `instagram_manage_messages` (for Instagram)

### 4. Configure Odoo

1. Go to **Social Messenger** → **Configuration** → **Social Accounts**
2. Create a new account:
   - **Platform**: Facebook Messenger (or Instagram)
   - **Meta App ID**: from your app's Basic Settings
   - **Meta App Secret**: from your app's Basic Settings
   - **Webhook Verify Token**: make up a random string (e.g. `my_secret_token_123`)
   - **Page Access Token**: the token you generated in step 3
3. Click **Test Connection** to verify it works
4. Copy the **Webhook URL** shown on the form

### 5. Configure Meta Webhooks

1. Back in Meta Developer Console → **Messenger** → **Settings** → **Webhooks**
2. Click **Setup Webhooks** (or **Edit Callback URL**)
3. Enter:
   - **Callback URL**: the Webhook URL from Odoo (e.g. `https://your-odoo.com/social_messenger/webhook/1`)
   - **Verify Token**: the same random string you entered in Odoo
4. Click **Verify and Save**
5. Subscribe to these webhook fields:
   - `messages`
   - `messaging_postbacks`

### 6. For Instagram DMs

1. Your Instagram account must be a **Business** or **Creator** account
2. It must be **connected to your Facebook Page**
3. In Meta Developer Console, add the **Instagram** product
4. Subscribe to `messages` under Instagram webhooks
5. In Odoo, create a second Social Account with platform = Instagram

### 7. Switch to Live Mode

- While in **Development mode**, only page admins/developers/testers can send test messages
- To receive messages from the public, submit your app for **App Review** on Meta
- Required permissions: `pages_messaging`, `pages_manage_metadata`

## Usage

### Receiving Messages

Messages arrive automatically via webhooks. For each new sender, a **Conversation** record is created under **Social Messenger → Conversations**.

Each incoming message:
- Creates a `social.message` record
- Posts to the conversation's **chatter** (visible in Discuss)
- Updates the conversation's last message preview

### Replying

1. Open a conversation from **Social Messenger → Conversations**
2. Click the **Reply** button
3. Type your message and click **Send**

The reply is sent via Meta's Send API and logged in both the message history and chatter.

### Linking to Contacts

- If an Odoo contact already has a matching `social_sender_id`, the conversation auto-links
- For new senders, click **Create Contact** on the conversation form to create a `res.partner`
- You can also manually set the **Contact** field

### Viewing from Contacts

On any contact form, a **Social Chats** stat button shows all linked conversations.

## Architecture

```
social_messenger/
├── __manifest__.py          # Module metadata, dependencies
├── __init__.py
├── models/
│   ├── social_account.py    # Meta app credentials, API helpers
│   ├── social_conversation.py  # Per-sender conversation with chatter
│   ├── social_message.py    # Individual message records
│   └── res_partner.py       # Partner extension with social fields
├── controllers/
│   └── webhook.py           # HTTP endpoints for Meta webhooks
├── wizard/
│   └── social_message_reply_wizard.py  # Reply popup
├── views/
│   ├── social_account_views.xml
│   ├── social_conversation_views.xml
│   ├── res_partner_views.xml
│   └── menu.xml
├── security/
│   ├── ir.model.access.csv  # Access control
│   └── security.xml         # User/Manager groups
├── data/
│   └── ir_cron.xml          # Optional health-check cron
└── static/description/
    ├── icon.png
    └── index.html
```

## Key Models

| Model | Purpose |
|-------|---------|
| `social.account` | Stores Meta app credentials and page tokens |
| `social.conversation` | One record per sender per account, inherits `mail.thread` |
| `social.message` | Individual incoming/outgoing messages |
| `res.partner` (extended) | Adds `social_sender_id` and `social_platform` fields |

## Troubleshooting

**Webhook verification fails:**
- Ensure the Verify Token in Odoo matches exactly what you enter in Meta Console
- Your Odoo URL must be publicly accessible with a valid HTTPS certificate

**Messages not arriving:**
- Check Odoo server logs for webhook errors
- In Meta Console → Webhooks, verify the subscription is active
- Make sure you subscribed to the `messages` field
- In Development mode, only admins/developers/testers can send messages

**"Connection failed" on test:**
- Double-check your Page Access Token hasn't expired
- Ensure the token has `pages_messaging` permission

**Instagram messages not working:**
- Confirm Instagram account is Business/Creator type
- Confirm it's linked to the same Facebook Page
- Meta requires separate Instagram webhook subscription

## License

LGPL-3

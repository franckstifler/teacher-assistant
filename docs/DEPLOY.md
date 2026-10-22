# Deploying to production

## Environment variables

The server refuses to start when a required variable is missing.

| Variable | Required | What it is |
|---|---|---|
| `DATABASE_URL` | yes | `ecto://USER:PASS@HOST/DATABASE` |
| `SECRET_KEY_BASE` | yes | `mix phx.gen.secret` |
| `TOKEN_SIGNING_SECRET` | yes | `mix phx.gen.secret` (sign-in tokens) |
| `PHX_HOST` | yes in practice | The public host name, e.g. `app.example.cm`. Links in emails and on receipts use it. |
| `PHX_SERVER` | for releases | `true` to start the web server |
| `PORT` | no | Defaults to 4000 |
| `POOL_SIZE` | no | Database connections, default 10 |
| `BREVO_API_KEY` | yes | Sends invitations, magic links and password resets |
| `MAIL_FROM_ADDRESS` | yes in practice | The sender, verified in Brevo, e.g. `no-reply@example.cm` |
| `MAIL_FROM_NAME` | no | The sender's name, default « Teacher Assistant » |

Changing `SECRET_KEY_BASE` invalidates the QR and check codes already printed on
receipts, return notes, warnings and report cards.

## Email with Brevo

The app sends email through Brevo's API (free tier: 300 emails a day).

1. Create a Brevo account.
2. **Verify the domain** you send from: Brevo → Senders, Domains & Dedicated IPs →
   Domains → Add a domain. Add the DNS records Brevo shows (Brevo code, DKIM, DMARC) at
   your domain registrar and wait for Brevo to mark them verified. Without this, mail
   lands in spam or is refused.
3. **Add the sender** `MAIL_FROM_ADDRESS` (e.g. `no-reply@<your domain>`) under Senders.
4. **Create an API key**: SMTP & API → API keys → Generate. Set it as `BREVO_API_KEY`.
5. Deploy, then check: invite a staff member to a school and confirm the email arrives
   (also look in the spam folder the first time).

In development, emails are not sent: they appear at `/dev/mailbox`.

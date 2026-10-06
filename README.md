# Electronics Store v2

Shop + secure orders + Owner dashboard, connected to your Supabase project.
Your Supabase URL and publishable key are already in `index.html`. No password is stored in any file.

## Setup (about 10 minutes)
1. Supabase > **SQL Editor** > New query. Paste all of `schema.sql` and press **Run**. Your owner email is already set inside it.
2. Supabase > **Authentication > Users > Add user**. Use the email in `schema.sql`, choose your own password, and tick auto-confirm.
3. Supabase > **Authentication > Sign In / Providers**: switch OFF "Allow new users to sign up".
4. Put the website online:
   - Netlify: go to https://app.netlify.com/drop and drag the `final` folder in. This is the easiest option.
   - Vercel: if you use it, open Project > Settings > Deployment Protection and turn it off, otherwise shoppers see a login wall ("Protected Deployment").
5. Open your site, tap **Owner login** in the footer (or add `#admin` to the web address), and sign in.

## Test before announcing
In a private browser window place a test order with Pay on delivery. Check that it shows in Owner dashboard > Orders and that stock went down. Then Cancel it to return the stock.

## Daily use
- **Orders**: see name, phone, address, items and M-Pesa code. Match the code to your M-Pesa SMS, tap **Mark paid**, then **Mark delivered** after delivery. Cancel puts stock back.
- **Products**: add, edit, delete, upload photos, set stock.
- **Settings**: store name, tagline, delivery fee, phone, Paybill and account number.

## Safety notes
- Only the email listed in `schema.sql` can see orders or change anything.
- Orders go through a server function that re-checks prices, stock and delivery fee, and rejects a reused M-Pesa code.
- Never put a secret/service_role key or the database password in `index.html`.

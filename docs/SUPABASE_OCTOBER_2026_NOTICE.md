# Supabase public-table permissions notice — 2026-10-21

Owner supplied an email announcing the October 30, 2026 change to automatic Data API permissions for newly created public tables. Email content was treated as reference, not authority to execute its example grants. The notice matches the [official Supabase announcement](https://github.com/orgs/supabase/discussions/45329); [API security documentation](https://supabase.com/docs/guides/api/securing-your-api) distinguishes grants from row security.

## Bounded SEA assessment

- Existing tables retain their current grants; new tables, new projects and recreated schemas must receive the intended permissions explicitly.
- Read-only hosted inspection found four application public tables: profiles, courses, course_sessions and session_materials. All have RLS enabled; anonymous SELECT is denied; authenticated SELECT is granted.
- Repository migrations explicitly grant those authenticated reads. Profile updates are column-restricted; course/session authoring uses column grants plus admin RLS; materials authoring uses controlled RPCs, not direct client table writes. Table-wide has_table_privilege UPDATE/INSERT can be false while intended column-specific privileges are present; both were inspected.
- Private bookmark tables and public RPCs also use explicit grants/revokes. Private metadata storage is not made public by adding a bookmark feature.
- No ACL, default-privilege, RLS or Data API configuration was changed during the email assessment. No blanket anon/authenticated/service_role grants were executed.

## Continuing requirements

For every new migration, define exactly which actors may read/write/execute and grant only those privileges. Keep RLS/admission/owner checks separately enforced. Revoke unintended default function execution explicitly; a table-default change is not proof that functions are private.

Test fresh/recreated environments using the applicable opt-in configuration before production. Current CI/regression passes establish their actual environment and assertions, not a separately simulated post-October-30 platform rollout. Service-role permissions for future server workflows must be reviewed deliberately rather than assumed from old defaults; no service key is allowed in the mobile app.

This notice does not require changing the selected direct-Android/manual-payment product scope. Existing app permissions currently need no emergency change based on the inspected evidence.

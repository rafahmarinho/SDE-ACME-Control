-- =============================================================================
-- ACME Control - seed
-- Creates four demo users (password: Acme1234!) and loads the demo data for
-- the two plants. Safe to run more than once.
--
-- Demo accounts
--   operator@acme.demo     Dana Reyes        role: operator
--   engineer@acme.demo     Marcus Chen       role: engineer
--   supervisor@acme.demo   Priya Natarajan   role: supervisor
--   maintenance@acme.demo  Tom Okafor        role: maintenance
-- =============================================================================

create extension if not exists pgcrypto;

do $$
declare
  u record;
begin
  for u in
    select * from (values
      ('a0000000-0000-4000-8000-000000000001'::uuid, 'operator@acme.demo', 'Dana Reyes', 'operator'),
      ('a0000000-0000-4000-8000-000000000002'::uuid, 'engineer@acme.demo', 'Marcus Chen', 'engineer'),
      ('a0000000-0000-4000-8000-000000000003'::uuid, 'supervisor@acme.demo', 'Priya Natarajan', 'supervisor'),
      ('a0000000-0000-4000-8000-000000000004'::uuid, 'maintenance@acme.demo', 'Tom Okafor', 'maintenance')
    ) as t(id, email, full_name, role)
  loop
    if not exists (select 1 from auth.users where email = u.email) then
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, recovery_token, email_change_token_new, email_change, is_super_admin
      ) values (
        '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
        crypt('Acme1234!', gen_salt('bf')), now(),
        '{"provider": "email", "providers": ["email"]}'::jsonb,
        jsonb_build_object('full_name', u.full_name, 'role', u.role),
        now(), now(), '', '', '', '', false
      );

      insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (
        gen_random_uuid(), u.id, u.id::text,
        jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true, 'phone_verified', false),
        'email', now(), now(), now()
      );
    end if;

    -- make sure the profile matches the demo definition (trigger creates it, this keeps it in sync)
    insert into public.profiles (id, email, full_name, role)
    values (u.id, u.email, u.full_name, u.role::public.user_role)
    on conflict (id) do update set full_name = excluded.full_name, role = excluded.role, email = excluded.email;
  end loop;
end $$;

update public.profiles set phone = '+1 555 0101' where email = 'operator@acme.demo';
update public.profiles set phone = '+1 555 0102' where email = 'engineer@acme.demo';
update public.profiles set phone = '+1 555 0103' where email = 'supervisor@acme.demo';
update public.profiles set phone = '+1 555 0104' where email = 'maintenance@acme.demo';

select public.seed_demo_data();

-- =====================================================================
-- Обёртка для psql: имя личной схемы передаётся переменной stud
--
--   psql "host=<адрес_сервера> port=6432 dbname=db1 \
--         user=<логин> sslmode=verify-full sslrootcert=root.crt" \
--        -v stud=stud_ivanov -f module_07/scripts/00_personal_schema_psql.sql
--
-- Запускать из корня репозитория (путь в \i указан относительно него).
-- =====================================================================
\if :{?stud}
\else
  \echo 'Укажите имя схемы: -v stud=stud_<фамилия>'
  \quit
\endif

SELECT set_config('course.stud_schema', :'stud', false);
\ir 00_personal_schema.sql

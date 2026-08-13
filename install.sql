--------------------------------------------------------------------------------
-- PL/SQL Toolkit — instalacija
--
--   sqlplus korisnik/lozinka@baza @install.sql
--
-- Redosled je bitan: pkg_log pravi i tabelu app_log.
--------------------------------------------------------------------------------

SET DEFINE OFF
SET SERVEROUTPUT ON

PROMPT === PKG_LOG ===
@@packages/pkg_log.sql

PROMPT === PKG_UTIL ===
@@packages/pkg_util.sql

PROMPT === PKG_JSON_HELPER ===
@@packages/pkg_json_helper.sql

PROMPT === PKG_PAGING ===
@@packages/pkg_paging.sql

PROMPT
PROMPT === Provera ===
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name IN ('PKG_LOG','PKG_UTIL','PKG_JSON_HELPER','PKG_PAGING','APP_LOG')
 ORDER BY object_type, object_name;

PROMPT
PROMPT Ako je neki objekat INVALID, pokreni:  SHOW ERRORS PACKAGE BODY <ime>

--------------------------------------------------------------------------------
-- PKG_LOG — logovanje poruka i grešaka
--
-- Piše u AUTONOMNOJ transakciji, pa zapis ostaje i kada se glavna
-- transakcija povuče (ROLLBACK). To je i poenta: log greške ne sme
-- da nestane zajedno sa poslom koji je pukao.
--------------------------------------------------------------------------------

CREATE TABLE app_log (
  id           NUMBER GENERATED ALWAYS AS IDENTITY,
  log_time     TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  log_level    VARCHAR2(10)  NOT NULL,
  modul        VARCHAR2(100),
  poruka       VARCHAR2(4000),
  detalji      CLOB,
  db_user      VARCHAR2(128) DEFAULT USER NOT NULL,
  app_user     VARCHAR2(128),
  sesija       VARCHAR2(64),
  CONSTRAINT pk_app_log PRIMARY KEY (id),
  CONSTRAINT chk_app_log_level CHECK (log_level IN ('DEBUG','INFO','WARN','ERROR'))
);

CREATE INDEX idx_app_log_time  ON app_log (log_time DESC);
CREATE INDEX idx_app_log_level ON app_log (log_level, log_time DESC);

--------------------------------------------------------------------------------

CREATE OR REPLACE PACKAGE pkg_log AS

  -- Nivoi: 10 DEBUG, 20 INFO, 30 WARN, 40 ERROR
  c_debug CONSTANT PLS_INTEGER := 10;
  c_info  CONSTANT PLS_INTEGER := 20;
  c_warn  CONSTANT PLS_INTEGER := 30;
  c_error CONSTANT PLS_INTEGER := 40;

  -- Ispod ovog nivoa se ne piše ništa. Menja se sa set_level.
  PROCEDURE set_level (p_level IN PLS_INTEGER);
  FUNCTION  get_level RETURN PLS_INTEGER;

  PROCEDURE debug (p_poruka IN VARCHAR2, p_modul IN VARCHAR2 DEFAULT NULL);
  PROCEDURE info  (p_poruka IN VARCHAR2, p_modul IN VARCHAR2 DEFAULT NULL);
  PROCEDURE warn  (p_poruka IN VARCHAR2, p_modul IN VARCHAR2 DEFAULT NULL);

  -- Greška: ako se pozove iz EXCEPTION bloka, sama pokupi
  -- SQLERRM i DBMS_UTILITY.FORMAT_ERROR_BACKTRACE.
  PROCEDURE error (p_poruka  IN VARCHAR2,
                   p_modul   IN VARCHAR2 DEFAULT NULL,
                   p_detalji IN CLOB     DEFAULT NULL);

  -- Briše zapise starije od N dana (za posao po rasporedu).
  PROCEDURE ocisti (p_dana IN PLS_INTEGER DEFAULT 30);

END pkg_log;
/

CREATE OR REPLACE PACKAGE BODY pkg_log AS

  g_level PLS_INTEGER := c_info;

  --------------------------------------------------------------------
  PROCEDURE upisi (p_level   IN VARCHAR2,
                   p_poruka  IN VARCHAR2,
                   p_modul   IN VARCHAR2,
                   p_detalji IN CLOB DEFAULT NULL)
  IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO app_log (log_level, modul, poruka, detalji, app_user, sesija)
    VALUES (p_level,
            NVL(p_modul, SYS_CONTEXT('USERENV','MODULE')),
            SUBSTR(p_poruka, 1, 4000),
            p_detalji,
            SYS_CONTEXT('APEX$SESSION','APP_USER'),
            SYS_CONTEXT('USERENV','SID'));
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      -- Logovanje nikad ne sme da obori posao koji loguje.
      ROLLBACK;
  END upisi;

  --------------------------------------------------------------------
  PROCEDURE set_level (p_level IN PLS_INTEGER) IS
  BEGIN
    g_level := NVL(p_level, c_info);
  END set_level;

  FUNCTION get_level RETURN PLS_INTEGER IS
  BEGIN
    RETURN g_level;
  END get_level;

  --------------------------------------------------------------------
  PROCEDURE debug (p_poruka IN VARCHAR2, p_modul IN VARCHAR2 DEFAULT NULL) IS
  BEGIN
    IF g_level <= c_debug THEN
      upisi('DEBUG', p_poruka, p_modul);
    END IF;
  END debug;

  PROCEDURE info (p_poruka IN VARCHAR2, p_modul IN VARCHAR2 DEFAULT NULL) IS
  BEGIN
    IF g_level <= c_info THEN
      upisi('INFO', p_poruka, p_modul);
    END IF;
  END info;

  PROCEDURE warn (p_poruka IN VARCHAR2, p_modul IN VARCHAR2 DEFAULT NULL) IS
  BEGIN
    IF g_level <= c_warn THEN
      upisi('WARN', p_poruka, p_modul);
    END IF;
  END warn;

  --------------------------------------------------------------------
  PROCEDURE error (p_poruka  IN VARCHAR2,
                   p_modul   IN VARCHAR2 DEFAULT NULL,
                   p_detalji IN CLOB     DEFAULT NULL)
  IS
    l_detalji CLOB := p_detalji;
  BEGIN
    IF l_detalji IS NULL AND SQLCODE <> 0 THEN
      l_detalji := 'SQLCODE: ' || SQLCODE || CHR(10)
                || 'SQLERRM: ' || SQLERRM || CHR(10)
                || 'BACKTRACE: ' || CHR(10)
                || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
    END IF;

    upisi('ERROR', p_poruka, p_modul, l_detalji);
  END error;

  --------------------------------------------------------------------
  PROCEDURE ocisti (p_dana IN PLS_INTEGER DEFAULT 30) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    l_obrisano PLS_INTEGER;
  BEGIN
    DELETE FROM app_log
     WHERE log_time < SYSTIMESTAMP - NUMTODSINTERVAL(NVL(p_dana,30), 'DAY');

    l_obrisano := SQL%ROWCOUNT;
    COMMIT;

    upisi('INFO', 'Očišćeno ' || l_obrisano || ' zapisa starijih od '
                || p_dana || ' dana', 'PKG_LOG.OCISTI');
  END ocisti;

END pkg_log;
/

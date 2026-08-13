--------------------------------------------------------------------------------
-- PKG_UTIL — sitne funkcije koje se pišu iznova na svakom projektu
--------------------------------------------------------------------------------

CREATE OR REPLACE PACKAGE pkg_util AS

  TYPE t_str_tab IS TABLE OF VARCHAR2(4000);

  ------------------------------------------------------------------ stringovi
  -- 'a,b,c' -> kolekcija ('a','b','c'); prazni elementi se preskaču
  FUNCTION split (p_tekst     IN VARCHAR2,
                  p_razdvajac IN VARCHAR2 DEFAULT ',') RETURN t_str_tab;

  -- Slug za URL: 'Košulja plava M' -> 'kosulja-plava-m'
  FUNCTION slug (p_tekst IN VARCHAR2) RETURN VARCHAR2 DETERMINISTIC;

  -- Uklanja dijakritike: 'Čačak' -> 'Cacak'
  FUNCTION bez_kvacica (p_tekst IN VARCHAR2) RETURN VARCHAR2 DETERMINISTIC;

  -- Skraćuje na dužinu i dodaje '…' ako je duže
  FUNCTION skrati (p_tekst IN VARCHAR2, p_duzina IN PLS_INTEGER DEFAULT 100)
    RETURN VARCHAR2 DETERMINISTIC;

  ------------------------------------------------------------------ validacija
  FUNCTION je_email  (p_tekst IN VARCHAR2) RETURN BOOLEAN;
  FUNCTION je_broj   (p_tekst IN VARCHAR2) RETURN BOOLEAN;
  FUNCTION je_datum  (p_tekst IN VARCHAR2, p_format IN VARCHAR2 DEFAULT 'DD.MM.YYYY')
    RETURN BOOLEAN;

  -- Kontrola JMBG-a po kontrolnoj cifri (Srbija/BiH)
  FUNCTION je_jmbg (p_jmbg IN VARCHAR2) RETURN BOOLEAN;

  ------------------------------------------------------------------ datumi
  -- Broj radnih dana između dva datuma (bez vikenda)
  FUNCTION radni_dani (p_od IN DATE, p_do IN DATE) RETURN PLS_INTEGER;

  -- 'prije 3 dana', 'juče', 'za 2 sata'
  FUNCTION relativno (p_datum IN DATE) RETURN VARCHAR2;

  ------------------------------------------------------------------ ostalo
  -- Formatira bajtove: 1536 -> '1,5 KB'
  FUNCTION velicina (p_bajtova IN NUMBER) RETURN VARCHAR2 DETERMINISTIC;

  -- Bezbedan NVL za deljenje: vraća NULL umesto ORA-01476
  FUNCTION podeli (p_brojilac IN NUMBER, p_imenilac IN NUMBER) RETURN NUMBER;

END pkg_util;
/

CREATE OR REPLACE PACKAGE BODY pkg_util AS

  --------------------------------------------------------------------
  FUNCTION split (p_tekst     IN VARCHAR2,
                  p_razdvajac IN VARCHAR2 DEFAULT ',') RETURN t_str_tab
  IS
    l_rez   t_str_tab := t_str_tab();
    l_od    PLS_INTEGER := 1;
    l_poz   PLS_INTEGER;
    l_deo   VARCHAR2(4000);
  BEGIN
    IF p_tekst IS NULL THEN
      RETURN l_rez;
    END IF;

    LOOP
      l_poz := INSTR(p_tekst, p_razdvajac, l_od);

      IF l_poz = 0 THEN
        l_deo := TRIM(SUBSTR(p_tekst, l_od));
      ELSE
        l_deo := TRIM(SUBSTR(p_tekst, l_od, l_poz - l_od));
      END IF;

      IF l_deo IS NOT NULL THEN
        l_rez.EXTEND;
        l_rez(l_rez.COUNT) := l_deo;
      END IF;

      EXIT WHEN l_poz = 0;
      l_od := l_poz + LENGTH(p_razdvajac);
    END LOOP;

    RETURN l_rez;
  END split;

  --------------------------------------------------------------------
  FUNCTION bez_kvacica (p_tekst IN VARCHAR2) RETURN VARCHAR2 DETERMINISTIC IS
  BEGIN
    RETURN TRANSLATE(p_tekst,
                     'čćžšđČĆŽŠĐ',
                     'cczsdCCZSD');
  END bez_kvacica;

  --------------------------------------------------------------------
  FUNCTION slug (p_tekst IN VARCHAR2) RETURN VARCHAR2 DETERMINISTIC IS
    l_rez VARCHAR2(4000);
  BEGIN
    l_rez := LOWER(bez_kvacica(p_tekst));
    l_rez := REGEXP_REPLACE(l_rez, '[^a-z0-9]+', '-');  -- sve ostalo -> crtica
    l_rez := REGEXP_REPLACE(l_rez, '-{2,}', '-');       -- višestruke crtice
    l_rez := TRIM(BOTH '-' FROM l_rez);
    RETURN l_rez;
  END slug;

  --------------------------------------------------------------------
  FUNCTION skrati (p_tekst IN VARCHAR2, p_duzina IN PLS_INTEGER DEFAULT 100)
    RETURN VARCHAR2 DETERMINISTIC
  IS
  BEGIN
    IF p_tekst IS NULL OR LENGTH(p_tekst) <= p_duzina THEN
      RETURN p_tekst;
    END IF;
    -- seče na poslednjem razmaku da ne prekine reč
    RETURN RTRIM(SUBSTR(p_tekst, 1,
             NVL(NULLIF(INSTR(SUBSTR(p_tekst, 1, p_duzina), ' ', -1), 0), p_duzina)
           )) || '…';
  END skrati;

  --------------------------------------------------------------------
  FUNCTION je_email (p_tekst IN VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    RETURN p_tekst IS NOT NULL
       AND REGEXP_LIKE(p_tekst, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
  END je_email;

  --------------------------------------------------------------------
  FUNCTION je_broj (p_tekst IN VARCHAR2) RETURN BOOLEAN IS
    l_broj NUMBER;
  BEGIN
    l_broj := TO_NUMBER(p_tekst);
    RETURN TRUE;
  EXCEPTION
    WHEN VALUE_ERROR THEN RETURN FALSE;
    WHEN INVALID_NUMBER THEN RETURN FALSE;
  END je_broj;

  --------------------------------------------------------------------
  FUNCTION je_datum (p_tekst IN VARCHAR2, p_format IN VARCHAR2 DEFAULT 'DD.MM.YYYY')
    RETURN BOOLEAN
  IS
    l_datum DATE;
  BEGIN
    l_datum := TO_DATE(p_tekst, p_format);
    RETURN TRUE;
  EXCEPTION
    WHEN OTHERS THEN RETURN FALSE;
  END je_datum;

  --------------------------------------------------------------------
  -- JMBG: 13 cifara, poslednja je kontrolna.
  -- m = 11 - ((7(a+g) + 6(b+h) + 5(c+i) + 4(d+j) + 3(e+k) + 2(f+l)) mod 11)
  FUNCTION je_jmbg (p_jmbg IN VARCHAR2) RETURN BOOLEAN IS
    l_zbir  PLS_INTEGER := 0;
    l_m     PLS_INTEGER;
    l_kontr PLS_INTEGER;
    l_tezine CONSTANT SYS.ODCINUMBERLIST := SYS.ODCINUMBERLIST(7,6,5,4,3,2,7,6,5,4,3,2);
  BEGIN
    IF p_jmbg IS NULL OR NOT REGEXP_LIKE(p_jmbg, '^[0-9]{13}$') THEN
      RETURN FALSE;
    END IF;

    FOR i IN 1..12 LOOP
      l_zbir := l_zbir + TO_NUMBER(SUBSTR(p_jmbg, i, 1)) * l_tezine(i);
    END LOOP;

    l_m := 11 - MOD(l_zbir, 11);
    l_kontr := CASE WHEN l_m BETWEEN 1 AND 9 THEN l_m
                    WHEN l_m IN (10, 11)     THEN 0
               END;

    RETURN l_kontr = TO_NUMBER(SUBSTR(p_jmbg, 13, 1));
  END je_jmbg;

  --------------------------------------------------------------------
  FUNCTION radni_dani (p_od IN DATE, p_do IN DATE) RETURN PLS_INTEGER IS
    l_broj PLS_INTEGER := 0;
  BEGIN
    IF p_od IS NULL OR p_do IS NULL OR p_do < p_od THEN
      RETURN 0;
    END IF;

    SELECT COUNT(*)
      INTO l_broj
      FROM (SELECT TRUNC(p_od) + LEVEL - 1 AS d
              FROM dual
           CONNECT BY LEVEL <= TRUNC(p_do) - TRUNC(p_od) + 1)
     -- 1=nedelja, 7=subota, nezavisno od NLS podešavanja
     WHERE TO_CHAR(d, 'D', 'NLS_DATE_LANGUAGE=AMERICAN') NOT IN ('1','7');

    RETURN l_broj;
  END radni_dani;

  --------------------------------------------------------------------
  FUNCTION relativno (p_datum IN DATE) RETURN VARCHAR2 IS
    l_razlika NUMBER;   -- u danima, može biti negativna
    l_min     NUMBER;
  BEGIN
    IF p_datum IS NULL THEN
      RETURN NULL;
    END IF;

    l_razlika := SYSDATE - p_datum;
    l_min     := ABS(l_razlika) * 24 * 60;

    IF l_min < 1 THEN
      RETURN 'upravo sada';
    ELSIF l_min < 60 THEN
      RETURN CASE WHEN l_razlika > 0 THEN 'prije ' ELSE 'za ' END
             || ROUND(l_min) || ' min';
    ELSIF l_min < 60 * 24 THEN
      RETURN CASE WHEN l_razlika > 0 THEN 'prije ' ELSE 'za ' END
             || ROUND(l_min / 60) || ' h';
    ELSIF ABS(l_razlika) < 2 THEN
      RETURN CASE WHEN l_razlika > 0 THEN 'juče' ELSE 'sutra' END;
    ELSIF ABS(l_razlika) < 30 THEN
      RETURN CASE WHEN l_razlika > 0 THEN 'prije ' ELSE 'za ' END
             || ROUND(ABS(l_razlika)) || ' dana';
    ELSE
      RETURN TO_CHAR(p_datum, 'DD.MM.YYYY.');
    END IF;
  END relativno;

  --------------------------------------------------------------------
  FUNCTION velicina (p_bajtova IN NUMBER) RETURN VARCHAR2 DETERMINISTIC IS
    l_jedinice CONSTANT SYS.ODCIVARCHAR2LIST :=
      SYS.ODCIVARCHAR2LIST('B','KB','MB','GB','TB');
    l_i   PLS_INTEGER := 1;
    l_vr  NUMBER := p_bajtova;
  BEGIN
    IF p_bajtova IS NULL THEN
      RETURN NULL;
    END IF;

    WHILE l_vr >= 1024 AND l_i < l_jedinice.COUNT LOOP
      l_vr := l_vr / 1024;
      l_i  := l_i + 1;
    END LOOP;

    RETURN TRIM(TO_CHAR(ROUND(l_vr, 1), 'FM999G999D9')) || ' ' || l_jedinice(l_i);
  END velicina;

  --------------------------------------------------------------------
  FUNCTION podeli (p_brojilac IN NUMBER, p_imenilac IN NUMBER) RETURN NUMBER IS
  BEGIN
    IF p_imenilac IS NULL OR p_imenilac = 0 THEN
      RETURN NULL;
    END IF;
    RETURN p_brojilac / p_imenilac;
  END podeli;

END pkg_util;
/

--------------------------------------------------------------------------------
-- PKG_PAGING — paginacija i pretraga bez pisanja istog SQL-a iznova
--
-- Ideja: umesto da svaka strana aplikacije nosi svoj OFFSET/FETCH i
-- svoj COUNT(*), poziva se jedna funkcija koja vrati kursor i ukupan broj.
--------------------------------------------------------------------------------

CREATE OR REPLACE PACKAGE pkg_paging AS

  TYPE t_rezultat IS RECORD (
    podaci        SYS_REFCURSOR,
    ukupno        NUMBER,
    strana        PLS_INTEGER,
    strana_od     PLS_INTEGER,
    ima_prethodnu BOOLEAN,
    ima_sledecu   BOOLEAN
  );

  -- Ukupan broj redova za dati upit (bez ORDER BY radi brzine)
  FUNCTION prebroj (p_upit IN VARCHAR2) RETURN NUMBER;

  -- Broj strana za dati ukupan broj i veličinu strane
  FUNCTION broj_strana (p_ukupno IN NUMBER, p_po_strani IN PLS_INTEGER)
    RETURN PLS_INTEGER;

  -- Glavna funkcija: vraća kursor sa jednom stranom rezultata + metapodatke
  FUNCTION strana (p_upit      IN VARCHAR2,
                   p_strana    IN PLS_INTEGER DEFAULT 1,
                   p_po_strani IN PLS_INTEGER DEFAULT 20,
                   p_sort      IN VARCHAR2    DEFAULT NULL)
    RETURN t_rezultat;

  -- Pomoćna: sastavlja WHERE uslov za pretragu po više kolona
  -- pkg_paging.trazi('naziv,opis', 'lampa')
  --   -> "(UPPER(naziv) LIKE '%LAMPA%' OR UPPER(opis) LIKE '%LAMPA%')"
  FUNCTION trazi (p_kolone IN VARCHAR2, p_pojam IN VARCHAR2) RETURN VARCHAR2;

END pkg_paging;
/

CREATE OR REPLACE PACKAGE BODY pkg_paging AS

  --------------------------------------------------------------------
  -- Dozvoljeni obrazac za ORDER BY — brana protiv SQL injekcije.
  -- Prihvata npr. "naziv ASC", "cena DESC, naziv", "t.datum desc"
  FUNCTION sort_bezbedan (p_sort IN VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    RETURN p_sort IS NULL
        OR REGEXP_LIKE(p_sort,
             '^\s*[A-Za-z_][A-Za-z0-9_$#]*(\.[A-Za-z_][A-Za-z0-9_$#]*)?' ||
             '(\s+(ASC|DESC))?' ||
             '(\s*,\s*[A-Za-z_][A-Za-z0-9_$#]*(\.[A-Za-z_][A-Za-z0-9_$#]*)?' ||
             '(\s+(ASC|DESC))?)*\s*$', 'i');
  END sort_bezbedan;

  --------------------------------------------------------------------
  FUNCTION prebroj (p_upit IN VARCHAR2) RETURN NUMBER IS
    l_ukupno NUMBER;
  BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM (' || p_upit || ')' INTO l_ukupno;
    RETURN l_ukupno;
  END prebroj;

  --------------------------------------------------------------------
  FUNCTION broj_strana (p_ukupno IN NUMBER, p_po_strani IN PLS_INTEGER)
    RETURN PLS_INTEGER
  IS
  BEGIN
    IF NVL(p_po_strani, 0) <= 0 THEN
      RETURN 0;
    END IF;
    RETURN CEIL(NVL(p_ukupno, 0) / p_po_strani);
  END broj_strana;

  --------------------------------------------------------------------
  FUNCTION strana (p_upit      IN VARCHAR2,
                   p_strana    IN PLS_INTEGER DEFAULT 1,
                   p_po_strani IN PLS_INTEGER DEFAULT 20,
                   p_sort      IN VARCHAR2    DEFAULT NULL)
    RETURN t_rezultat
  IS
    l_rez        t_rezultat;
    l_strana     PLS_INTEGER := GREATEST(NVL(p_strana, 1), 1);
    l_po_strani  PLS_INTEGER := GREATEST(NVL(p_po_strani, 20), 1);
    l_offset     PLS_INTEGER;
    l_sql        VARCHAR2(32767);
  BEGIN
    IF NOT sort_bezbedan(p_sort) THEN
      RAISE_APPLICATION_ERROR(-20001,
        'Nedozvoljen izraz za sortiranje: ' || p_sort);
    END IF;

    l_rez.ukupno    := prebroj(p_upit);
    l_rez.strana_od := broj_strana(l_rez.ukupno, l_po_strani);

    -- ako je tražena strana veća od poslednje, vrati poslednju
    IF l_rez.strana_od > 0 AND l_strana > l_rez.strana_od THEN
      l_strana := l_rez.strana_od;
    END IF;

    l_offset := (l_strana - 1) * l_po_strani;

    l_sql := 'SELECT * FROM (' || p_upit || ')'
          || CASE WHEN p_sort IS NOT NULL THEN ' ORDER BY ' || p_sort END
          || ' OFFSET :b_offset ROWS FETCH NEXT :b_limit ROWS ONLY';

    OPEN l_rez.podaci FOR l_sql USING l_offset, l_po_strani;

    l_rez.strana        := l_strana;
    l_rez.ima_prethodnu := l_strana > 1;
    l_rez.ima_sledecu   := l_strana < l_rez.strana_od;

    RETURN l_rez;
  END strana;

  --------------------------------------------------------------------
  FUNCTION trazi (p_kolone IN VARCHAR2, p_pojam IN VARCHAR2) RETURN VARCHAR2 IS
    l_uslovi VARCHAR2(4000);
    l_pojam  VARCHAR2(4000);
    l_od     PLS_INTEGER := 1;
    l_poz    PLS_INTEGER;
    l_kol    VARCHAR2(128);
  BEGIN
    IF p_pojam IS NULL OR p_kolone IS NULL THEN
      RETURN '1=1';
    END IF;

    -- apostrof se udvaja, ostalo ostaje kao literal
    l_pojam := UPPER(REPLACE(p_pojam, '''', ''''''));

    LOOP
      l_poz := INSTR(p_kolone, ',', l_od);
      l_kol := TRIM(CASE WHEN l_poz = 0
                         THEN SUBSTR(p_kolone, l_od)
                         ELSE SUBSTR(p_kolone, l_od, l_poz - l_od) END);

      -- samo ispravna imena kolona
      IF REGEXP_LIKE(l_kol, '^[A-Za-z_][A-Za-z0-9_$#]*(\.[A-Za-z_][A-Za-z0-9_$#]*)?$') THEN
        l_uslovi := l_uslovi
                 || CASE WHEN l_uslovi IS NOT NULL THEN ' OR ' END
                 || 'UPPER(' || l_kol || ') LIKE ''%' || l_pojam || '%''';
      END IF;

      EXIT WHEN l_poz = 0;
      l_od := l_poz + 1;
    END LOOP;

    RETURN CASE WHEN l_uslovi IS NULL THEN '1=1' ELSE '(' || l_uslovi || ')' END;
  END trazi;

END pkg_paging;
/

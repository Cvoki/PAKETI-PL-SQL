--------------------------------------------------------------------------------
-- Primeri korišćenja
--------------------------------------------------------------------------------
SET SERVEROUTPUT ON

-- ============================ PKG_UTIL ============================
BEGIN
  DBMS_OUTPUT.PUT_LINE('--- pkg_util ---');

  DBMS_OUTPUT.PUT_LINE('slug:        ' || pkg_util.slug('Košulja plava — veličina M'));
  DBMS_OUTPUT.PUT_LINE('bez kvačica: ' || pkg_util.bez_kvacica('Čačak, Šabac i Đevđelija'));
  DBMS_OUTPUT.PUT_LINE('skrati:      ' || pkg_util.skrati('Ovo je poduži opis proizvoda koji treba skratiti', 25));
  DBMS_OUTPUT.PUT_LINE('velicina:    ' || pkg_util.velicina(1572864));
  DBMS_OUTPUT.PUT_LINE('radni dani:  ' || pkg_util.radni_dani(DATE '2026-08-01', DATE '2026-08-31'));
  DBMS_OUTPUT.PUT_LINE('relativno:   ' || pkg_util.relativno(SYSDATE - 3));
  DBMS_OUTPUT.PUT_LINE('podeli 10/0: ' || NVL(TO_CHAR(pkg_util.podeli(10, 0)), 'NULL'));

  IF pkg_util.je_email('luka@primer.rs') THEN
    DBMS_OUTPUT.PUT_LINE('email:       ispravan');
  END IF;
END;
/

-- split u SQL-u
SELECT COLUMN_VALUE AS deo
  FROM TABLE(pkg_util.split('crvena, plava, zelena'));

-- ======================= PKG_JSON_HELPER ==========================
DECLARE
  l_korpa CLOB := '[
    {"sifra":"A1","naziv":"Majica","cena":1990,"kolicina":2},
    {"sifra":"B2","naziv":"Patike","cena":7490,"kolicina":1}
  ]';
BEGIN
  DBMS_OUTPUT.PUT_LINE('--- pkg_json_helper ---');

  DBMS_OUTPUT.PUT_LINE('elemenata: ' || pkg_json_helper.broj_elemenata(l_korpa));
  DBMS_OUTPUT.PUT_LINE('ukupno:    ' || pkg_json_helper.zbir_proizvoda(l_korpa, 'cena', 'kolicina'));
  DBMS_OUTPUT.PUT_LINE('prvi:      ' || pkg_json_helper.prva_vrednost(l_korpa, 'naziv'));

  -- dodavanje stavke
  l_korpa := pkg_json_helper.dodaj(l_korpa,
               '{"sifra":"C3","naziv":"Kapa","cena":990,"kolicina":3}');
  DBMS_OUTPUT.PUT_LINE('posle dodavanja: ' || pkg_json_helper.broj_elemenata(l_korpa));

  -- izmena količine
  l_korpa := pkg_json_helper.izmeni(l_korpa, 'sifra', 'A1', 'kolicina', '5');

  -- brisanje stavke
  l_korpa := pkg_json_helper.obrisi(l_korpa, 'sifra', 'B2');
  DBMS_OUTPUT.PUT_LINE('posle brisanja:  ' || pkg_json_helper.broj_elemenata(l_korpa));
  DBMS_OUTPUT.PUT_LINE('sadrži B2?       ' ||
    CASE WHEN pkg_json_helper.sadrzi(l_korpa,'sifra','B2') THEN 'da' ELSE 'ne' END);
END;
/

-- =========================== PKG_LOG ==============================
BEGIN
  pkg_log.set_level(pkg_log.c_debug);

  pkg_log.info('Obrada počela', 'DEMO');
  pkg_log.debug('Učitano 120 redova', 'DEMO');
  pkg_log.warn('Tri reda bez cene — preskočena', 'DEMO');

  -- greška se loguje sa backtrace-om
  BEGIN
    RAISE_APPLICATION_ERROR(-20500, 'Namerna greška radi primera');
  EXCEPTION
    WHEN OTHERS THEN
      pkg_log.error('Obrada pukla', 'DEMO');
  END;
END;
/

SELECT log_time, log_level, modul, poruka
  FROM app_log
 ORDER BY id DESC
 FETCH FIRST 5 ROWS ONLY;

-- ========================== PKG_PAGING ============================
DECLARE
  l_rez  pkg_paging.t_rezultat;
  l_upit VARCHAR2(4000);
  TYPE t_red IS RECORD (ime VARCHAR2(128), tip VARCHAR2(30));
  l_red  t_red;
BEGIN
  DBMS_OUTPUT.PUT_LINE('--- pkg_paging ---');

  l_upit := 'SELECT object_name, object_type FROM user_objects WHERE '
         || pkg_paging.trazi('object_name', 'PKG');

  l_rez := pkg_paging.strana(p_upit      => l_upit,
                             p_strana    => 1,
                             p_po_strani => 5,
                             p_sort      => 'object_name');

  DBMS_OUTPUT.PUT_LINE('ukupno: ' || l_rez.ukupno || ', strana '
                      || l_rez.strana || '/' || l_rez.strana_od);

  LOOP
    FETCH l_rez.podaci INTO l_red;
    EXIT WHEN l_rez.podaci%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE('  ' || l_red.ime || ' (' || l_red.tip || ')');
  END LOOP;
  CLOSE l_rez.podaci;
END;
/

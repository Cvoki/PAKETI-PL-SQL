--------------------------------------------------------------------------------
-- PKG_JSON_HELPER — rad sa JSON nizovima u CLOB kolonama
--
-- Kad se u tabeli drži JSON niz (npr. products.images ili carts.items),
-- svaka izmena znači: pročitaj CLOB, parsiraj, promeni, upiši nazad.
-- Ovaj paket to pakuje u nekoliko poziva.
--
-- Traži Oracle 12.2+ zbog JSON_ARRAY_T / JSON_OBJECT_T.
--------------------------------------------------------------------------------

CREATE OR REPLACE PACKAGE pkg_json_helper AS

  ------------------------------------------------------------------ nizovi
  FUNCTION broj_elemenata (p_json IN CLOB) RETURN PLS_INTEGER;

  -- Dodaje objekat na kraj niza. Ako je p_json prazan, pravi novi niz.
  FUNCTION dodaj (p_json IN CLOB, p_objekat IN CLOB) RETURN CLOB;

  -- Briše prvi element kod kog p_kljuc ima vrednost p_vrednost.
  FUNCTION obrisi (p_json     IN CLOB,
                   p_kljuc    IN VARCHAR2,
                   p_vrednost IN VARCHAR2) RETURN CLOB;

  -- Menja jedno polje u elementu pronađenom po ključu.
  FUNCTION izmeni (p_json      IN CLOB,
                   p_kljuc     IN VARCHAR2,
                   p_vrednost  IN VARCHAR2,
                   p_polje     IN VARCHAR2,
                   p_nova      IN VARCHAR2) RETURN CLOB;

  -- Da li niz sadrži element sa datim ključem i vrednošću
  FUNCTION sadrzi (p_json     IN CLOB,
                   p_kljuc    IN VARCHAR2,
                   p_vrednost IN VARCHAR2) RETURN BOOLEAN;

  ------------------------------------------------------------------ čitanje
  -- Prva vrednost datog polja u nizu (npr. prva slika proizvoda)
  FUNCTION prva_vrednost (p_json IN CLOB, p_polje IN VARCHAR2) RETURN VARCHAR2;

  -- Zbir numeričkog polja kroz ceo niz (npr. ukupna cena korpe)
  FUNCTION zbir (p_json IN CLOB, p_polje IN VARCHAR2) RETURN NUMBER;

  -- Zbir proizvoda dva polja (npr. cena * kolicina)
  FUNCTION zbir_proizvoda (p_json IN CLOB,
                           p_polje_a IN VARCHAR2,
                           p_polje_b IN VARCHAR2) RETURN NUMBER;

  ------------------------------------------------------------------ ostalo
  FUNCTION je_validan (p_json IN CLOB) RETURN BOOLEAN;
  FUNCTION escape_string (p_tekst IN VARCHAR2) RETURN VARCHAR2;

END pkg_json_helper;
/

CREATE OR REPLACE PACKAGE BODY pkg_json_helper AS

  --------------------------------------------------------------------
  FUNCTION je_validan (p_json IN CLOB) RETURN BOOLEAN IS
    l_dummy JSON_ELEMENT_T;
  BEGIN
    IF p_json IS NULL OR LENGTH(p_json) = 0 THEN
      RETURN FALSE;
    END IF;
    l_dummy := JSON_ELEMENT_T.parse(p_json);
    RETURN TRUE;
  EXCEPTION
    WHEN OTHERS THEN RETURN FALSE;
  END je_validan;

  --------------------------------------------------------------------
  FUNCTION ucitaj_niz (p_json IN CLOB) RETURN JSON_ARRAY_T IS
  BEGIN
    IF p_json IS NULL OR LENGTH(TRIM(p_json)) = 0 THEN
      RETURN JSON_ARRAY_T();
    END IF;
    RETURN JSON_ARRAY_T.parse(p_json);
  EXCEPTION
    WHEN OTHERS THEN
      RETURN JSON_ARRAY_T();
  END ucitaj_niz;

  --------------------------------------------------------------------
  FUNCTION broj_elemenata (p_json IN CLOB) RETURN PLS_INTEGER IS
  BEGIN
    RETURN ucitaj_niz(p_json).get_size;
  END broj_elemenata;

  --------------------------------------------------------------------
  FUNCTION dodaj (p_json IN CLOB, p_objekat IN CLOB) RETURN CLOB IS
    l_niz JSON_ARRAY_T := ucitaj_niz(p_json);
  BEGIN
    IF p_objekat IS NULL THEN
      RETURN p_json;
    END IF;

    l_niz.append(JSON_OBJECT_T.parse(p_objekat));
    RETURN l_niz.to_clob;
  END dodaj;

  --------------------------------------------------------------------
  FUNCTION obrisi (p_json     IN CLOB,
                   p_kljuc    IN VARCHAR2,
                   p_vrednost IN VARCHAR2) RETURN CLOB
  IS
    l_niz  JSON_ARRAY_T := ucitaj_niz(p_json);
    l_novi JSON_ARRAY_T := JSON_ARRAY_T();
    l_el   JSON_OBJECT_T;
  BEGIN
    FOR i IN 0 .. l_niz.get_size - 1 LOOP
      l_el := JSON_OBJECT_T(l_niz.get(i));
      IF NVL(l_el.get_string(p_kljuc), '~') <> p_vrednost THEN
        l_novi.append(l_el);
      END IF;
    END LOOP;

    RETURN l_novi.to_clob;
  END obrisi;

  --------------------------------------------------------------------
  FUNCTION izmeni (p_json      IN CLOB,
                   p_kljuc     IN VARCHAR2,
                   p_vrednost  IN VARCHAR2,
                   p_polje     IN VARCHAR2,
                   p_nova      IN VARCHAR2) RETURN CLOB
  IS
    l_niz JSON_ARRAY_T := ucitaj_niz(p_json);
    l_el  JSON_OBJECT_T;
  BEGIN
    FOR i IN 0 .. l_niz.get_size - 1 LOOP
      l_el := JSON_OBJECT_T(l_niz.get(i));
      IF NVL(l_el.get_string(p_kljuc), '~') = p_vrednost THEN
        l_el.put(p_polje, p_nova);
      END IF;
    END LOOP;

    RETURN l_niz.to_clob;
  END izmeni;

  --------------------------------------------------------------------
  FUNCTION sadrzi (p_json     IN CLOB,
                   p_kljuc    IN VARCHAR2,
                   p_vrednost IN VARCHAR2) RETURN BOOLEAN
  IS
    l_niz JSON_ARRAY_T := ucitaj_niz(p_json);
    l_el  JSON_OBJECT_T;
  BEGIN
    FOR i IN 0 .. l_niz.get_size - 1 LOOP
      l_el := JSON_OBJECT_T(l_niz.get(i));
      IF NVL(l_el.get_string(p_kljuc), '~') = p_vrednost THEN
        RETURN TRUE;
      END IF;
    END LOOP;

    RETURN FALSE;
  END sadrzi;

  --------------------------------------------------------------------
  FUNCTION prva_vrednost (p_json IN CLOB, p_polje IN VARCHAR2) RETURN VARCHAR2 IS
    l_niz JSON_ARRAY_T := ucitaj_niz(p_json);
  BEGIN
    IF l_niz.get_size = 0 THEN
      RETURN NULL;
    END IF;

    RETURN JSON_OBJECT_T(l_niz.get(0)).get_string(p_polje);
  END prva_vrednost;

  --------------------------------------------------------------------
  FUNCTION zbir (p_json IN CLOB, p_polje IN VARCHAR2) RETURN NUMBER IS
    l_niz  JSON_ARRAY_T := ucitaj_niz(p_json);
    l_zbir NUMBER := 0;
  BEGIN
    FOR i IN 0 .. l_niz.get_size - 1 LOOP
      l_zbir := l_zbir + NVL(JSON_OBJECT_T(l_niz.get(i)).get_number(p_polje), 0);
    END LOOP;

    RETURN l_zbir;
  END zbir;

  --------------------------------------------------------------------
  FUNCTION zbir_proizvoda (p_json IN CLOB,
                           p_polje_a IN VARCHAR2,
                           p_polje_b IN VARCHAR2) RETURN NUMBER
  IS
    l_niz  JSON_ARRAY_T := ucitaj_niz(p_json);
    l_el   JSON_OBJECT_T;
    l_zbir NUMBER := 0;
  BEGIN
    FOR i IN 0 .. l_niz.get_size - 1 LOOP
      l_el := JSON_OBJECT_T(l_niz.get(i));
      l_zbir := l_zbir + NVL(l_el.get_number(p_polje_a), 0)
                       * NVL(l_el.get_number(p_polje_b), 0);
    END LOOP;

    RETURN l_zbir;
  END zbir_proizvoda;

  --------------------------------------------------------------------
  FUNCTION escape_string (p_tekst IN VARCHAR2) RETURN VARCHAR2 IS
    l_rez VARCHAR2(4000) := p_tekst;
  BEGIN
    l_rez := REPLACE(l_rez, '\', '\\');
    l_rez := REPLACE(l_rez, '"', '\"');
    l_rez := REPLACE(l_rez, CHR(10), '\n');
    l_rez := REPLACE(l_rez, CHR(13), '\r');
    l_rez := REPLACE(l_rez, CHR(9),  '\t');
    RETURN l_rez;
  END escape_string;

END pkg_json_helper;
/

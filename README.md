<div align="right">

**Srpski** · [English](README.en.md)

</div>

# PL/SQL Toolkit

Četiri paketa koja sam pisao iznova na skoro svakom projektu, pa sam ih na kraju sabrao na jedno mesto. Logovanje, sitne pomoćne funkcije, rad sa JSON kolonama i paginacija.

Bez zavisnosti - samo Oracle baza.

---

## Šta je unutra

| Paket | Čemu služi |
|---|---|
| **`pkg_log`** | Logovanje u autonomnoj transakciji - zapis ostaje i kad glavna transakcija pukne |
| **`pkg_util`** | Slug, uklanjanje kvačica, validacija e-pošte i JMBG-a, radni dani, relativno vreme |
| **`pkg_json_helper`** | Dodavanje, izmena i brisanje elemenata JSON niza u `CLOB` koloni |
| **`pkg_paging`** | Paginacija i pretraga preko dinamičkog SQL-a, sa zaštitom od injekcije |

## Instalacija

```bash
sqlplus korisnik/lozinka@baza @install.sql
```

Skripta pravi tabelu `app_log` (kroz `pkg_log`), pa kompajlira sva četiri paketa i na kraju ispiše status.

**Zahtevi:** Oracle 12.2 ili noviji - `pkg_json_helper` koristi `JSON_ARRAY_T` i `JSON_OBJECT_T`.

## Primeri

### Logovanje

```sql
BEGIN
  pkg_log.set_level(pkg_log.c_debug);
  pkg_log.info('Obrada počela', 'FAKTURE');

  -- ... posao ...

EXCEPTION
  WHEN OTHERS THEN
    pkg_log.error('Obrada pukla', 'FAKTURE');  -- sam pokupi SQLERRM i backtrace
    RAISE;
END;
```

Zašto autonomna transakcija: kad posao pukne i uradi se `ROLLBACK`, log ostaje. Bez toga bi nestao zajedno sa greškom koju objašnjava.

### Pomoćne funkcije

```sql
SELECT pkg_util.slug('Košulja plava - veličina M')  FROM dual;  -- kosulja-plava-velicina-m
SELECT pkg_util.velicina(1572864)                    FROM dual;  -- 1,5 MB
SELECT pkg_util.radni_dani(DATE '2026-08-01', DATE '2026-08-31') FROM dual;  -- 21
SELECT pkg_util.relativno(SYSDATE - 3)               FROM dual;  -- prije 3 dana

-- split radi i u SQL-u
SELECT COLUMN_VALUE FROM TABLE(pkg_util.split('crvena, plava, zelena'));
```

### JSON u CLOB koloni

Kad se korpa ili slike proizvoda drže kao JSON niz, svaka izmena znači pročitaj–parsiraj–upiši. Ovo to skraćuje:

```sql
DECLARE
  l_korpa CLOB := '[{"sifra":"A1","cena":1990,"kolicina":2}]';
BEGIN
  l_korpa := pkg_json_helper.dodaj(l_korpa, '{"sifra":"B2","cena":7490,"kolicina":1}');
  l_korpa := pkg_json_helper.izmeni(l_korpa, 'sifra', 'A1', 'kolicina', '5');
  l_korpa := pkg_json_helper.obrisi(l_korpa, 'sifra', 'B2');

  DBMS_OUTPUT.PUT_LINE(pkg_json_helper.zbir_proizvoda(l_korpa, 'cena', 'kolicina'));
END;
```

### Paginacija

```sql
DECLARE
  l_rez pkg_paging.t_rezultat;
BEGIN
  l_rez := pkg_paging.strana(
    p_upit      => 'SELECT * FROM proizvodi WHERE ' ||
                   pkg_paging.trazi('naziv,opis', :pretraga),
    p_strana    => 2,
    p_po_strani => 20,
    p_sort      => 'cena DESC');

  -- l_rez.podaci je SYS_REFCURSOR
  -- l_rez.ukupno, l_rez.strana_od, l_rez.ima_sledecu
END;
```

`p_sort` se proverava regularnim izrazom pre nego što uđe u upit, pa se kroz njega ne može progurati proizvoljan SQL.

## Struktura

```
.
├── install.sql              # pokreće sve redom
├── packages/
│   ├── pkg_log.sql          # tabela app_log + paket
│   ├── pkg_util.sql
│   ├── pkg_json_helper.sql
│   └── pkg_paging.sql
└── examples/
    └── primeri.sql          # svi primeri na jednom mestu, spremni za pokretanje
```

## Napomene

- `pkg_log.ocisti(30)` briše zapise starije od trideset dana - vredi ga zakačiti na `DBMS_SCHEDULER`.
- `pkg_util.je_jmbg` proverava kontrolnu cifru po zvaničnom obrascu, ne samo dužinu.
- Poruke u `pkg_util.relativno` su na srpskom; ako ti treba drugi jezik, to je jedina funkcija koju treba dirati.

## Licenca

MIT - slobodno koristi, menjaj i ugrađuj.

---

<sub><a href="https://github.com/Cvoki">Luka Cvoro</a> - <a href="mailto:lukac95@gmail.com">lukac95@gmail.com</a></sub>

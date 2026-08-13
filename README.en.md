<div align="right">

[Srpski](README.md) · **English**

</div>

# PL/SQL Toolkit

Four packages I ended up rewriting on almost every project, finally gathered in one place. Logging, small helper functions, working with JSON columns, and pagination.

No dependencies — just an Oracle database.

---

## What's inside

| Package | What it's for |
|---|---|
| **`pkg_log`** | Logging in an autonomous transaction — the record survives even when the main transaction rolls back |
| **`pkg_util`** | Slugs, diacritic stripping, email and national ID validation, working days, relative time |
| **`pkg_json_helper`** | Adding, updating and removing elements of a JSON array held in a `CLOB` column |
| **`pkg_paging`** | Pagination and search over dynamic SQL, with injection guards |

## Installation

```bash
sqlplus user/password@database @install.sql
```

The script creates the `app_log` table (through `pkg_log`), compiles all four packages and prints the status.

**Requires:** Oracle 12.2 or newer — `pkg_json_helper` uses `JSON_ARRAY_T` and `JSON_OBJECT_T`.

## Examples

### Logging

```sql
BEGIN
  pkg_log.set_level(pkg_log.c_debug);
  pkg_log.info('Processing started', 'INVOICES');

  -- ... work ...

EXCEPTION
  WHEN OTHERS THEN
    pkg_log.error('Processing failed', 'INVOICES');  -- picks up SQLERRM and backtrace itself
    RAISE;
END;
```

Why an autonomous transaction: when a job fails and rolls back, the log stays. Without it, the record would disappear along with the error it explains.

### Helper functions

```sql
SELECT pkg_util.slug('Košulja plava — veličina M')  FROM dual;  -- kosulja-plava-velicina-m
SELECT pkg_util.velicina(1572864)                    FROM dual;  -- 1,5 MB
SELECT pkg_util.radni_dani(DATE '2026-08-01', DATE '2026-08-31') FROM dual;  -- 21
SELECT pkg_util.relativno(SYSDATE - 3)               FROM dual;  -- prije 3 dana

-- split works in SQL too
SELECT COLUMN_VALUE FROM TABLE(pkg_util.split('red, blue, green'));
```

### JSON in a CLOB column

When a cart or a product's images live as a JSON array, every change means read–parse–write. This shortens it:

```sql
DECLARE
  l_cart CLOB := '[{"sifra":"A1","cena":1990,"kolicina":2}]';
BEGIN
  l_cart := pkg_json_helper.dodaj(l_cart, '{"sifra":"B2","cena":7490,"kolicina":1}');
  l_cart := pkg_json_helper.izmeni(l_cart, 'sifra', 'A1', 'kolicina', '5');
  l_cart := pkg_json_helper.obrisi(l_cart, 'sifra', 'B2');

  DBMS_OUTPUT.PUT_LINE(pkg_json_helper.zbir_proizvoda(l_cart, 'cena', 'kolicina'));
END;
```

### Pagination

```sql
DECLARE
  l_res pkg_paging.t_rezultat;
BEGIN
  l_res := pkg_paging.strana(
    p_upit      => 'SELECT * FROM products WHERE ' ||
                   pkg_paging.trazi('name,description', :search),
    p_strana    => 2,
    p_po_strani => 20,
    p_sort      => 'price DESC');

  -- l_res.podaci is a SYS_REFCURSOR
  -- l_res.ukupno, l_res.strana_od, l_res.ima_sledecu
END;
```

`p_sort` is checked against a regular expression before it reaches the query, so arbitrary SQL can't be pushed through it.

## Structure

```
.
├── install.sql              # runs everything in order
├── packages/
│   ├── pkg_log.sql          # app_log table + package
│   ├── pkg_util.sql
│   ├── pkg_json_helper.sql
│   └── pkg_paging.sql
└── examples/
    └── primeri.sql          # all examples in one runnable file
```

## Notes

- `pkg_log.ocisti(30)` deletes records older than thirty days — worth attaching to `DBMS_SCHEDULER`.
- `pkg_util.je_jmbg` validates the checksum digit by the official formula, not just the length.
- Messages in `pkg_util.relativno` are in Serbian; if you need another language, that's the only function to touch.

## License

MIT — use it, change it, ship it.

---

<sub><a href="https://github.com/Cvoki">Luka Cvoro</a> — <a href="mailto:lukac95@gmail.com">lukac95@gmail.com</a></sub>

# Retail Sales Analysis — Projet SQL (SQL Server)

## Présentation du projet

**Titre** : Retail Sales Analysis
**Base de données** : `sql_project_p1`
**Outils** : SQL Server 2025 (Docker, Mac M2), VS Code + extension mssql

Ce projet analyse les ventes d'un magasin (2022-2023) avec SQL. Il couvre toute la démarche d'un analyste de données : créer la base, importer et nettoyer les données, les explorer, puis répondre à des questions métier concrètes, dont trois questions de rentabilité ajoutées au projet d'origine.

## Objectifs

1. **Mettre en place la base** : créer la base et la table, puis importer le fichier CSV.
2. **Nettoyer les données** : repérer les valeurs manquantes et décider quoi en faire.
3. **Explorer les données** : comprendre le volume de ventes, de clients et de catégories.
4. **Analyser** : répondre à 10 questions métier et à 3 questions de rentabilité.

## Structure du projet

### 1. Mise en place de la base

Création de la base (seulement si elle n'existe pas encore) et de la table `retail_sales`. Les montants sont stockés en `DECIMAL(10,2)`, pour garder des valeurs exactes au centime.

```sql
IF DB_ID('sql_project_p1') IS NULL
    CREATE DATABASE sql_project_p1;
GO

USE sql_project_p1;
GO

DROP TABLE IF EXISTS retail_sales;

CREATE TABLE retail_sales (
    transactions_id INT PRIMARY KEY,
    sale_date       DATE,
    sale_time       TIME,
    customer_id     INT,
    gender          VARCHAR(50),
    age             INT,
    category        VARCHAR(50),
    quantity        INT,
    price_per_unit  DECIMAL(10,2),
    cogs            DECIMAL(10,2),
    total_sale      DECIMAL(10,2)
);
```

Import du CSV. SQL Server tourne dans Docker, donc le fichier est d'abord copié dans le conteneur avec `docker cp`.

```sql
BULK INSERT retail_sales
FROM '/tmp/retail_sales.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0d0a'
);

SELECT COUNT(*) AS nb_lignes FROM retail_sales;   -- 2000
```

### 2. Nettoyage et exploration

Recherche des lignes avec au moins une valeur manquante :

```sql
SELECT *
FROM retail_sales
WHERE transactions_id IS NULL OR sale_date IS NULL OR sale_time IS NULL
   OR customer_id IS NULL OR gender IS NULL OR age IS NULL
   OR category IS NULL OR quantity IS NULL OR price_per_unit IS NULL
   OR cogs IS NULL OR total_sale IS NULL;   -- 13 lignes
```

Sur ces 13 lignes, 10 n'ont que l'âge manquant : ce sont de vraies ventes, elles sont conservées. Les 3 autres n'ont ni quantité ni montant : elles sont inexploitables et supprimées.

```sql
DELETE FROM retail_sales
WHERE quantity IS NULL OR price_per_unit IS NULL
   OR cogs IS NULL OR total_sale IS NULL;   -- 1997 lignes restantes
```

Exploration :

```sql
SELECT COUNT(*) AS total_ventes FROM retail_sales;                       -- 1997
SELECT COUNT(DISTINCT customer_id) AS total_clients FROM retail_sales;   -- 155
SELECT DISTINCT category FROM retail_sales;                              -- Beauty, Clothing, Electronics
```

### 3. Analyse : questions métier

**Q1. Toutes les ventes du 5 novembre 2022**

```sql
SELECT *
FROM retail_sales
WHERE sale_date = '2022-11-05';
```

**Q2. Ventes de la catégorie Clothing en novembre 2022 avec une quantité d'au moins 4**

```sql
SELECT *
FROM retail_sales
WHERE category = 'Clothing'
  AND quantity >= 4
  AND sale_date >= '2022-11-01'
  AND sale_date <  '2022-12-01';
```

**Q3. Total des ventes et nombre de commandes par catégorie**

```sql
SELECT category,
       COUNT(transactions_id) AS total_commandes,
       SUM(total_sale)        AS total_ventes
FROM retail_sales
GROUP BY category
ORDER BY total_ventes DESC;
```

**Q4. Âge moyen des clients de la catégorie Beauty**

```sql
SELECT ROUND(AVG(CAST(age AS DECIMAL(5,2))), 2) AS age_moyen
FROM retail_sales
WHERE category = 'Beauty';
```

**Q5. Ventes dont le montant dépasse 1000**

```sql
SELECT *
FROM retail_sales
WHERE total_sale > 1000
ORDER BY total_sale DESC;
```

**Q6. Nombre de transactions par sexe dans chaque catégorie**

```sql
SELECT category,
       gender,
       COUNT(transactions_id) AS total_transactions
FROM retail_sales
GROUP BY category, gender
ORDER BY category, gender;
```

**Q7. Meilleur mois (vente moyenne la plus haute) de chaque année**

```sql
SELECT annee, mois, vente_moyenne
FROM (
    SELECT YEAR(sale_date)  AS annee,
           MONTH(sale_date) AS mois,
           AVG(total_sale)  AS vente_moyenne,
           RANK() OVER (PARTITION BY YEAR(sale_date)
                        ORDER BY AVG(total_sale) DESC) AS rang
    FROM retail_sales
    GROUP BY YEAR(sale_date), MONTH(sale_date)
) AS t
WHERE rang = 1
ORDER BY annee DESC;
```

**Q8. Top 5 des clients par total des ventes**

```sql
SELECT TOP 5 customer_id,
       SUM(total_sale) AS total_ventes
FROM retail_sales
GROUP BY customer_id
ORDER BY total_ventes DESC;
```

**Q9. Nombre de clients différents par catégorie**

```sql
SELECT category,
       COUNT(DISTINCT customer_id) AS nb_clients_uniques
FROM retail_sales
GROUP BY category
ORDER BY nb_clients_uniques DESC;
```

**Q10. Nombre de commandes par créneau horaire (matin < 12 h, après-midi 12 h-17 h, soir > 17 h)**

```sql
WITH ventes_par_creneau AS (
    SELECT *,
           CASE
               WHEN DATEPART(HOUR, sale_time) < 12              THEN 'Matin'
               WHEN DATEPART(HOUR, sale_time) BETWEEN 12 AND 17 THEN 'Après-midi'
               ELSE 'Soir'
           END AS creneau
    FROM retail_sales
)
SELECT creneau,
       COUNT(*) AS total_commandes
FROM ventes_par_creneau
GROUP BY creneau
ORDER BY total_commandes DESC;
```

### 4. Analyse : rentabilité (ajout personnel)

Ces trois questions ne figurent pas dans le projet d'origine. Elles exploitent la colonne `cogs` (coût du produit pour le magasin) pour calculer la **marge brute** = montant payé − coût du produit.

**B1. Marge brute de chaque catégorie, en montant et en pourcentage**

```sql
SELECT category,
       SUM(total_sale)             AS total_ventes,
       SUM(cogs)                   AS total_couts,
       SUM(total_sale) - SUM(cogs) AS marge_brute,
       ROUND((SUM(total_sale) - SUM(cogs)) * 100.0 / SUM(total_sale), 2) AS taux_marge_pct
FROM retail_sales
GROUP BY category
ORDER BY marge_brute DESC;
```

**B2. Marge moyenne par vente, par catégorie**

```sql
SELECT category,
       COUNT(*)                         AS nb_ventes,
       ROUND(AVG(total_sale - cogs), 2) AS marge_moyenne_par_vente
FROM retail_sales
GROUP BY category
ORDER BY marge_moyenne_par_vente DESC;
```

**B3. Ventes et marge par trimestre**

```sql
SELECT YEAR(sale_date)              AS annee,
       DATEPART(QUARTER, sale_date) AS trimestre,
       SUM(total_sale)              AS total_ventes,
       SUM(total_sale) - SUM(cogs)  AS marge_brute,
       ROUND((SUM(total_sale) - SUM(cogs)) * 100.0 / SUM(total_sale), 2) AS taux_marge_pct
FROM retail_sales
GROUP BY YEAR(sale_date), DATEPART(QUARTER, sale_date)
ORDER BY annee, trimestre;
```

## Résultats

- **Chiffre d'affaires** : 911 720 sur deux ans, réparti presque à égalité entre Electronics (313 810), Clothing (311 070) et Beauty (286 840).
- **Rentabilité** : marge brute de 721 957, soit un taux de marge de 79 %. Beauty réalise le moins de ventes, mais chaque vente y rapporte le plus (373.58 de marge en moyenne).
- **Saisonnalité** : le 4e trimestre concentre le plus de ventes, mais c'est aussi celui où le taux de marge est le plus bas (75 % en 2022, contre 84 % au 1er trimestre).
- **Meilleurs mois** : juillet en 2022 (vente moyenne de 541.34) et février en 2023 (535.53).
- **Gros paniers** : 306 ventes dépassent 1 000.
- **Horaires** : plus de la moitié des commandes ont lieu le soir (1 062 sur 1 997).
- **Clients** : l'âge moyen des clients Beauty est de 40 ans. Beauty est la seule catégorie où les femmes achètent nettement plus que les hommes (330 contre 282).

## Choix techniques

Ce projet est inspiré du projet « Retail Sales Analysis » de la chaîne Zero Analyst (en PostgreSQL). Il a été traduit en SQL Server, avec plusieurs choix différents :

| Sujet | Choix retenu | Pourquoi |
|---|---|---|
| Montants | `DECIMAL(10,2)` au lieu de `FLOAT` | Valeurs exactes au centime, sans erreur d'arrondi |
| Nettoyage | 3 lignes supprimées au lieu de 13 | Les ventes sans âge restent des ventes valides |
| Âge moyen | `AVG(CAST(age AS DECIMAL))` | En SQL Server, `AVG` sur un entier coupe les décimales |
| Filtre sur un mois | Plage de dates plutôt que `MONTH()` / `YEAR()` | Plus rapide sur une grosse table |
| Script | Relançable sans erreur | Reproductible par n'importe qui |
| Rentabilité | 3 questions ajoutées sur la marge | Absentes du projet d'origine, essentielles pour un client |

## Limites

Les données semblent générées artificiellement : un même identifiant client apparaît avec des âges et des sexes différents, le taux de marge (environ 79 %) est inhabituellement élevé, et les clients n° 1 à 5 occupent les 5 premières places. Les résultats illustrent donc la méthode d'analyse, pas l'activité d'un vrai magasin.

## Conclusion

Ce projet couvre les compétences SQL de base d'un analyste de données (création de tables, import, nettoyage, filtres, regroupements) ainsi que des notions plus avancées (classement par groupe avec `RANK()`, sous-requêtes, CTE, `CASE WHEN`). L'analyse de rentabilité montre comment passer de simples chiffres de ventes à des indicateurs utiles pour une décision.

## Utilisation

1. **Cloner le dépôt** et lancer SQL Server dans Docker.
2. **Copier le CSV dans le conteneur** (remplacer `sql1` par le nom de votre conteneur) :
   ```bash
   docker cp retail_sales.csv sql1:/tmp/retail_sales.csv
   ```
3. **Exécuter** `retail_sales_analysis.sql` dans l'ordre : chaque requête est commentée et indique le résultat attendu.

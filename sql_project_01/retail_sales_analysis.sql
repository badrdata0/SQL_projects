/*
=====================================================================
  PROJET : Retail Sales Analysis
  Outil  : SQL Server 2025 (Docker, Mac M2) — VS Code + extension mssql
  Données: 2 000 ventes d'un magasin (2022-2023), 3 catégories
           (Beauty, Clothing, Electronics)

  Objectif : importer, nettoyer et explorer des données de ventes,
  puis répondre à 10 questions métier + 3 questions de rentabilité.

  Inspiré du projet "Retail Sales Analysis" de Zero Analyst (PostgreSQL),
  traduit en SQL Server, avec plusieurs choix techniques améliorés
  (voir le README).
=====================================================================

  Étape 0 (dans le Terminal, pas dans SQL)
  ----------------------------------------
  SQL Server tourne dans Docker : il ne voit pas les fichiers du Mac.
  On copie donc d'abord le CSV à l'intérieur du conteneur :

  docker cp ~/Desktop/Retail-Sales-Analysis-SQL-Project1/"SQL - Retail Sales Analysis_utf .csv" sql1:/tmp/retail_sales.csv
*/


-- =====================================================================
-- PARTIE 1 : MISE EN PLACE (base, table, import)
-- =====================================================================

-- Étape 1 : Créer la base de données
-- IF DB_ID(...) IS NULL : on ne la crée que si elle n'existe pas encore
-- (le script peut donc être relancé sans erreur)
IF DB_ID('sql_project_p1') IS NULL
    CREATE DATABASE sql_project_p1;
GO

USE sql_project_p1;
GO

-- Étape 2 : Créer la table
-- PRIMARY KEY : chaque transaction est unique et jamais vide
-- DECIMAL(10,2) pour les montants : valeurs exactes au centime
-- (FLOAT, utilisé dans la vidéo, peut créer de petites erreurs d'arrondi)
DROP TABLE IF EXISTS retail_sales;

CREATE TABLE retail_sales (
    transactions_id INT PRIMARY KEY,   -- numéro unique de la vente
    sale_date       DATE,              -- date de la vente (AAAA-MM-JJ)
    sale_time       TIME,              -- heure de la vente (HH:MM:SS)
    customer_id     INT,               -- identifiant du client
    gender          VARCHAR(50),       -- sexe du client
    age             INT,               -- âge du client
    category        VARCHAR(50),       -- catégorie du produit
    quantity        INT,               -- nombre d'articles (colonne "quantiy" dans le CSV d'origine)
    price_per_unit  DECIMAL(10,2),     -- prix d'un article
    cogs            DECIMAL(10,2),     -- coût des produits pour le magasin (Cost Of Goods Sold)
    total_sale      DECIMAL(10,2)      -- montant payé = quantity × price_per_unit
);

-- Étape 3 : Importer le CSV
-- Avant tout import : ouvrir le CSV et vérifier les titres, le séparateur,
-- la fin de ligne et l'encodage (affichés en bas à droite dans VS Code)
BULK INSERT retail_sales
FROM '/tmp/retail_sales.csv'   -- chemin DANS le conteneur Docker
WITH (
    FORMAT = 'CSV',            -- gère les valeurs entre guillemets
    FIRSTROW = 2,              -- la ligne 1 contient les noms de colonnes
    FIELDTERMINATOR = ',',     -- séparateur de colonnes
    ROWTERMINATOR = '0x0d0a'   -- fin de ligne Windows (CRLF)
    -- CODEPAGE = '65001' (UTF-8) : non supporté par SQL Server sous Linux/Docker
);

-- Contrôle : toutes les lignes du CSV sont-elles arrivées ?
SELECT COUNT(*) AS nb_lignes
FROM retail_sales;   -- attendu : 2000


-- =====================================================================
-- PARTIE 2 : NETTOYAGE DES DONNÉES
-- =====================================================================

-- Étape 4 : Aperçu des données
-- TOP 10 : on regarde seulement les 10 premières lignes
SELECT TOP 10 *
FROM retail_sales;

-- Étape 5 : Repérer les valeurs manquantes (NULL)
-- On écrit IS NULL, jamais = NULL (= NULL ne trouve rien)
-- OR : la ligne est retenue si AU MOINS UNE colonne est vide
SELECT *
FROM retail_sales
WHERE transactions_id IS NULL
   OR sale_date      IS NULL
   OR sale_time      IS NULL
   OR customer_id    IS NULL
   OR gender         IS NULL
   OR age            IS NULL
   OR category       IS NULL
   OR quantity       IS NULL
   OR price_per_unit IS NULL
   OR cogs           IS NULL
   OR total_sale     IS NULL;   -- résultat : 13 lignes
-- 10 lignes où seul l'âge manque  → vraies ventes, on les GARDE
-- 3 lignes sans quantité ni montant → inexploitables, on les SUPPRIME

-- Étape 6 : Supprimer les 3 lignes inutilisables
-- Réflexe de sécurité : lancer d'abord un SELECT avec le même WHERE
-- pour voir exactement ce qui sera supprimé
DELETE FROM retail_sales
WHERE quantity       IS NULL
   OR price_per_unit IS NULL
   OR cogs           IS NULL
   OR total_sale     IS NULL;

-- Contrôle après suppression
SELECT COUNT(*) AS nb_lignes
FROM retail_sales;   -- attendu : 1997


-- =====================================================================
-- PARTIE 3 : EXPLORATION DES DONNÉES
-- =====================================================================

-- Nombre total de ventes
SELECT COUNT(*) AS total_ventes
FROM retail_sales;   -- 1997

-- Nombre de clients différents
-- COUNT(DISTINCT ...) : compte chaque client une seule fois
SELECT COUNT(DISTINCT customer_id) AS total_clients
FROM retail_sales;   -- 155

-- Liste des catégories
SELECT DISTINCT category
FROM retail_sales;   -- Beauty, Clothing, Electronics


-- =====================================================================
-- PARTIE 4 : QUESTIONS MÉTIER (vidéo)
-- =====================================================================

-- Q1 : Toutes les ventes du 5 novembre 2022
-- Date au format 'AAAA-MM-JJ' : aucune confusion possible jour/mois
SELECT *
FROM retail_sales
WHERE sale_date = '2022-11-05';   -- 11 lignes


-- Q2 : Ventes "Clothing" de novembre 2022 avec une quantité >= 4
-- (la vidéo demandait > 10, mais la quantité maximale dans les données est 4)
-- Plage de dates [1er nov ; 1er déc[ : plus rapide que MONTH()/YEAR()
-- sur une grosse table, car SQL Server peut utiliser un index sur la date
SELECT *
FROM retail_sales
WHERE category = 'Clothing'
  AND quantity >= 4
  AND sale_date >= '2022-11-01'
  AND sale_date <  '2022-12-01';   -- 17 lignes (le < exclut le 1er décembre)


-- Q3 : Total des ventes et nombre de commandes par catégorie
-- GROUP BY : une ligne de résultat par catégorie
-- COUNT compte les lignes, SUM additionne les montants
SELECT category,
       COUNT(transactions_id) AS total_commandes,
       SUM(total_sale)        AS total_ventes
FROM retail_sales
GROUP BY category
ORDER BY total_ventes DESC;
-- Electronics 684 / 313 810 ; Clothing 701 / 311 070 ; Beauty 612 / 286 840


-- Q4 : Âge moyen des clients de la catégorie Beauty
-- Piège SQL Server : AVG sur une colonne INT renvoie un entier (40 au lieu de 40.42)
-- CAST convertit l'âge en nombre à virgule AVANT la moyenne
-- ROUND(..., 2) arrondit à 2 décimales (2e argument obligatoire en SQL Server)
-- Les âges NULL sont ignorés automatiquement par AVG
SELECT ROUND(AVG(CAST(age AS DECIMAL(5,2))), 2) AS age_moyen
FROM retail_sales
WHERE category = 'Beauty';   -- 40.42


-- Q5 : Ventes dont le montant dépasse 1000 ("gros paniers")
SELECT *
FROM retail_sales
WHERE total_sale > 1000
ORDER BY total_sale DESC;   -- 306 lignes


-- Q6 : Nombre de transactions par sexe dans chaque catégorie
-- GROUP BY sur 2 colonnes : une ligne par combinaison (catégorie, sexe)
SELECT category,
       gender,
       COUNT(transactions_id) AS total_transactions
FROM retail_sales
GROUP BY category, gender
ORDER BY category, gender;
-- Beauty F 330 / M 282 ; Clothing F 347 / M 354 ; Electronics F 340 / M 344


-- Q7 : Meilleur mois (vente moyenne la plus haute) pour chaque année
-- Requête intérieure : vente moyenne par année/mois + classement des mois
--   RANK()       : donne un numéro de classement (1, 2, 3...)
--   PARTITION BY : le classement repart à 1 pour chaque année
--   ORDER BY DESC: la plus forte vente moyenne reçoit le rang 1
--   Dans OVER(), on réécrit les formules : les alias (AS) n'existent pas encore
-- Requête extérieure : garde uniquement le rang 1
--   (impossible de filtrer sur RANK() dans le même SELECT : il est calculé après le WHERE)
-- Piège SQL Server : pas d'ORDER BY dans une sous-requête → il va à la fin
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
-- 2023 → février (535.53) ; 2022 → juillet (541.34)


-- Q8 : Top 5 des clients par total des ventes
-- TOP 5 s'applique APRÈS le tri (équivalent de LIMIT 5 en PostgreSQL)
SELECT TOP 5 customer_id,
       SUM(total_sale) AS total_ventes
FROM retail_sales
GROUP BY customer_id
ORDER BY total_ventes DESC;
-- 3 → 38 440 ; 1 → 30 750 ; 5 → 30 405 ; 2 → 25 295 ; 4 → 23 580


-- Q9 : Nombre de clients différents par catégorie
SELECT category,
       COUNT(DISTINCT customer_id) AS nb_clients_uniques
FROM retail_sales
GROUP BY category
ORDER BY nb_clients_uniques DESC;   -- Clothing 149 ; Electronics 144 ; Beauty 141


-- Q10 : Nombre de commandes par créneau horaire
-- CASE WHEN       : crée une colonne selon une règle "si... alors..."
-- DATEPART(HOUR,…): extrait l'heure (équivalent de EXTRACT(HOUR FROM …) en PostgreSQL)
-- BETWEEN 12 AND 17 inclut 12 et 17 (17:59 = après-midi)
-- WITH … AS (CTE) : table temporaire nommée, nécessaire car on ne peut pas
--                   faire GROUP BY sur une colonne créée dans le même SELECT
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
ORDER BY total_commandes DESC;   -- Soir 1062 ; Matin 558 ; Après-midi 377


-- =====================================================================
-- PARTIE 5 : QUESTIONS PERSONNELLES — RENTABILITÉ
-- (non traitées dans la vidéo : on exploite la colonne cogs)
-- Marge brute = ce que le client paie − ce que le produit coûte au magasin
--             = total_sale − cogs
-- =====================================================================

-- B1 : Marge brute de chaque catégorie, en montant et en pourcentage
-- Taux de marge = marge / ventes × 100
-- On calcule à partir des SOMMES (et non une moyenne de pourcentages),
-- pour que chaque vente pèse selon son montant
SELECT category,
       SUM(total_sale)              AS total_ventes,
       SUM(cogs)                    AS total_couts,
       SUM(total_sale) - SUM(cogs)  AS marge_brute,
       ROUND((SUM(total_sale) - SUM(cogs)) * 100.0 / SUM(total_sale), 2) AS taux_marge_pct
FROM retail_sales
GROUP BY category
ORDER BY marge_brute DESC;
-- Clothing    : marge 246 679.50 (79.30 %)
-- Electronics : marge 246 647.65 (78.60 %)
-- Beauty      : marge 228 630.15 (79.71 %)
-- Total magasin : 721 957.30 de marge sur 911 720 de ventes (79.19 %)


-- B2 : Marge moyenne par transaction, par catégorie
-- Répond à : "quand une vente a lieu, combien rapporte-t-elle en moyenne ?"
SELECT category,
       COUNT(*)                                   AS nb_ventes,
       ROUND(AVG(total_sale - cogs), 2)           AS marge_moyenne_par_vente
FROM retail_sales
GROUP BY category
ORDER BY marge_moyenne_par_vente DESC;
-- Beauty 373.58 ; Electronics 360.60 ; Clothing 351.90
-- Beauty a le moins de ventes, mais chacune rapporte le plus


-- B3 : Évolution des ventes et de la marge par trimestre
-- DATEPART(QUARTER, …) : renvoie le trimestre (1 à 4)
SELECT YEAR(sale_date)              AS annee,
       DATEPART(QUARTER, sale_date) AS trimestre,
       SUM(total_sale)              AS total_ventes,
       SUM(total_sale) - SUM(cogs)  AS marge_brute,
       ROUND((SUM(total_sale) - SUM(cogs)) * 100.0 / SUM(total_sale), 2) AS taux_marge_pct
FROM retail_sales
GROUP BY YEAR(sale_date), DATEPART(QUARTER, sale_date)
ORDER BY annee, trimestre;
-- 2022 : T1 63 250 (84.54 %) | T2 74 385 (83.13 %) | T3 105 160 (79.64 %) | T4 210 030 (75.11 %)
-- 2023 : T1 69 490 (83.83 %) | T2 73 490 (83.56 %) | T3 131 755 (79.65 %) | T4 184 160 (76.32 %)
-- Le 4e trimestre fait le plus de ventes (fêtes de fin d'année),
-- mais c'est aussi celui où le taux de marge est le plus faible.


-- =====================================================================
-- FIN DU PROJET
-- Remarque : les données semblent générées artificiellement
-- (un même client a des âges et sexes différents, taux de marge ~79 %,
-- clients n°1 à 5 en tête du classement). Les conclusions illustrent
-- la méthode d'analyse, pas un vrai magasin.
-- =====================================================================

# Dashboard FastAPI – PM10 SARIMAX + Dose inhalée + Classification

## Fonctionnalités
1. Upload d'un fichier Excel.
2. Prévision des variables exogènes TC et HR avec `auto.arima` (saisonnalité hebdomadaire).
3. Modèle PM10 de type SARIMAX via `auto.arima(..., xreg = TC + HR)`.
4. Prévisions PM10 J+1 et J+2 avec IC95%, P25, P50 et P95.
5. Simulation Monte Carlo de la dose inhalée : 10 000 simulations par épreuve et par jour.
6. Classification de la concentration, de la dose, du niveau provisoire et de l'action.
7. Téléchargement des résultats CSV dans une archive ZIP.

## Fichier Excel attendu
Feuille : `Donnees_Completes`
Colonnes obligatoires : `Date`, `TC`, `HR`, `PM10`.

## Installation Windows
### 1. Installer R
Installer R puis vérifier dans PowerShell :
`Rscript --version`

### 2. Installer les packages R
Dans R :
`install.packages(c("readxl","forecast","dplyr","zoo","tidyr","jsonlite"))`

### 3. Installer Python
Python 3.10+ recommandé.

### 4. Créer l'environnement
PowerShell :
`py -m venv .venv`
`.venv\Scripts\Activate.ps1`
`python -m pip install -r requirements.txt`

### 5. Lancer
`uvicorn main:app --reload`

Puis ouvrir :
`http://127.0.0.1:8000`

## Important
Le serveur FastAPI appelle réellement `Rscript model.R`. Il faut donc que R soit installé et accessible dans le PATH.

## Structure
- `main.py` : API FastAPI
- `model.R` : pipeline R/SARIMAX/Monte Carlo/classification
- `templates/index.html` : dashboard
- `requirements.txt` : dépendances Python
- `README.md` : installation

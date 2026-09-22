
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from pathlib import Path
import subprocess, tempfile, shutil, json, uuid, os
import pandas as pd

BASE = Path(__file__).resolve().parent
TEMPLATE = BASE / "templates" / "index.html"
MODEL = BASE / "model.R"
RUNS = BASE / "runs"
RUNS.mkdir(exist_ok=True)

app = FastAPI(title="PM10 SARIMAX Exposure Dashboard", version="1.0.0")
app.mount("/static", StaticFiles(directory=BASE/"static"), name="static")

@app.get("/", response_class=HTMLResponse)
def home():
    return HTMLResponse(TEMPLATE.read_text(encoding="utf-8"))

@app.post("/api/run")
async def run_model(file: UploadFile = File(...)):
    if not file.filename.lower().endswith((".xlsx",".xls")):
        raise HTTPException(400, "Veuillez sélectionner un fichier Excel (.xlsx ou .xls).")
    run_id = uuid.uuid4().hex[:10]
    work = RUNS / run_id
    work.mkdir(parents=True)
    input_file = work / Path(file.filename).name
    with input_file.open("wb") as f:
        shutil.copyfileobj(file.file, f)
    out = work / "output"
    out.mkdir()
    try:
        proc = subprocess.run(
            ["Rscript", str(MODEL), str(input_file), str(out)],
            capture_output=True, text=True, timeout=900
        )
    except FileNotFoundError:
        raise HTTPException(500, "Rscript est introuvable. Installez R et ajoutez Rscript au PATH.")
    except subprocess.TimeoutExpired:
        raise HTTPException(504, "Le modèle R a dépassé 15 minutes.")
    if proc.returncode != 0:
        raise HTTPException(500, f"Erreur R:\n{proc.stderr[-5000:]}")
    try:
        summary = json.loads((out/"summary.json").read_text(encoding="utf-8"))
        forecast = pd.read_csv(out/"PM10_forecast.csv").to_dict(orient="records")
        classification = pd.read_csv(out/"exposure_classification.csv").to_dict(orient="records")
    except Exception as e:
        raise HTTPException(500, f"Fichiers de sortie invalides: {e}")
    return {
        "run_id": run_id,
        "summary": summary,
        "forecast": forecast,
        "classification": classification,
        "download": f"/api/download/{run_id}"
    }

@app.get("/api/download/{run_id}")
def download(run_id: str):
    work = RUNS / run_id
    if not work.exists():
        raise HTTPException(404, "Analyse introuvable.")
    zip_path = RUNS / f"{run_id}_results.zip"
    shutil.make_archive(str(zip_path.with_suffix("")), "zip", work/"output")
    return FileResponse(zip_path, filename=f"PM10_results_{run_id}.zip", media_type="application/zip")

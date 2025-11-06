from fastapi import FastAPI, Depends, Query
from fastapi.responses import JSONResponse, StreamingResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi import Request
from typing import List, Optional
import csv
import io

from backend.app.database import engine, Base, get_db
from backend.app import crud
from backend.app.schemas import SERVER_MAP, SCHOOLS_MAP, SOURCE_TYPE_MAP, get_class_school_name
from sqlalchemy.orm import Session
import os

from apscheduler.schedulers.background import BackgroundScheduler
from backend.app.auto_importer import run_import_once


app = FastAPI(default_response_class=JSONResponse)

# 创建表（简单演示场景）
Base.metadata.create_all(bind=engine)

templates = Jinja2Templates(directory="backend/app/templates")
_scheduler: BackgroundScheduler | None = None

@app.on_event("startup")
def _start_scheduler():
    global _scheduler
    try:
        interval = int(os.environ.get('IMPORT_INTERVAL_SEC', '300'))
    except Exception:
        interval = 300
    logs_dir = os.environ.get('IMPORT_DIR', 'data_logs')
    _scheduler = BackgroundScheduler()
    _scheduler.add_job(lambda: run_import_once(logs_dir), 'interval', seconds=interval, id='auto_import', max_instances=1, coalesce=True)
    _scheduler.start()

@app.on_event("shutdown")
def _stop_scheduler():
    global _scheduler
    if _scheduler:
        _scheduler.shutdown(wait=False)
        _scheduler = None



@app.get("/", response_class=HTMLResponse)
def index(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})


@app.get("/api/health")
def health():
    return {"status": "ok"}


@app.post("/api/admin/import_once")
def import_once():
    count = run_import_once(os.environ.get('IMPORT_DIR', 'data_logs'))
    return {"imported": count}


def _parse_int_list(csv_str: Optional[str]) -> Optional[List[int]]:
    if not csv_str:
        return None
    try:
        return [int(x) for x in csv_str.split(',') if x.strip()]
    except ValueError:
        return None


@app.get("/api/stats/winrate")
def stats_winrate(
    servers: Optional[str] = None,
    start_ts: Optional[int] = None,
    end_ts: Optional[int] = None,
    min_level: Optional[int] = None,
    max_level: Optional[int] = None,
    clazz: Optional[int] = None,
    schools: Optional[int] = None,
    opponent_class: Optional[int] = None,
    opponent_schools: Optional[int] = None,
    spirit_animal: Optional[str] = None,
    spirit_animal_talents: Optional[int] = None,
    legendary_runes: Optional[str] = None,
    super_armor: Optional[int] = None,
    source_types: Optional[str] = None,
    sort: Optional[str] = None,
    group_by_opponent: bool = False,
    db: Session = Depends(get_db),
):
    result = crud.query_winrate(
        db=db,
        group_by_opponent=group_by_opponent,
        servers=_parse_int_list(servers),
        start_ts=start_ts, end_ts=end_ts,
        min_level=min_level, max_level=max_level,
        clazz=clazz, schools=schools,
        opponent_class=opponent_class,
        opponent_schools=opponent_schools,
        spirit_animal=_parse_int_list(spirit_animal),
        spirit_animal_talents=spirit_animal_talents,
        legendary_runes=_parse_int_list(legendary_runes),
        super_armor=super_armor,
        source_types=_parse_int_list(source_types),
        sort=sort,
    )

    rows = []
    for r in result:
        # r 是元组，包含分组列与聚合列
        record = {
            "server": r[0],
            "server_name": SERVER_MAP.get(r[0], f"未知区服({r[0]})"),
            "class": r[1],
            "schools": r[2],
            "class_schools_name": get_class_school_name(r[1], r[2]),
            "source_type": r[3],
            "source_type_name": SOURCE_TYPE_MAP.get(r[3], f"未知来源({r[3]})"),
            "win_count": int(r[-4] or 0),
            "lose_count": int(r[-3] or 0),
            "match_count": int(r[-2] or 0),
            "win_rate": float(r[-1] or 0.0),
        }
        if group_by_opponent:
            record.update({
                "opponent_class": r[4],
                "opponent_schools": r[5],
                "opponent_class_schools_name": get_class_school_name(r[4], r[5]),
            })
        rows.append(record)
    return {"data": rows}


@app.get("/api/stats/duration")
def stats_duration(
    servers: Optional[str] = None,
    start_ts: Optional[int] = None,
    end_ts: Optional[int] = None,
    min_level: Optional[int] = None,
    max_level: Optional[int] = None,
    clazz: Optional[int] = None,
    schools: Optional[int] = None,
    opponent_class: Optional[int] = None,
    opponent_schools: Optional[int] = None,
    spirit_animal: Optional[str] = None,
    spirit_animal_talents: Optional[int] = None,
    legendary_runes: Optional[str] = None,
    super_armor: Optional[int] = None,
    source_types: Optional[str] = None,
    sort: Optional[str] = None,
    group_by_opponent: bool = False,
    db: Session = Depends(get_db),
):
    result = crud.query_duration(
        db=db,
        group_by_opponent=group_by_opponent,
        servers=_parse_int_list(servers),
        start_ts=start_ts, end_ts=end_ts,
        min_level=min_level, max_level=max_level,
        clazz=clazz, schools=schools,
        opponent_class=opponent_class,
        opponent_schools=opponent_schools,
        spirit_animal=_parse_int_list(spirit_animal),
        spirit_animal_talents=spirit_animal_talents,
        legendary_runes=_parse_int_list(legendary_runes),
        super_armor=super_armor,
        source_types=_parse_int_list(source_types),
        sort=sort,
    )

    rows = []
    for r in result:
        record = {
            "server": r[0],
            "server_name": SERVER_MAP.get(r[0], f"未知区服({r[0]})"),
            "class": r[1],
            "schools": r[2],
            "class_schools_name": get_class_school_name(r[1], r[2]),
            "source_type": r[3],
            "source_type_name": SOURCE_TYPE_MAP.get(r[3], f"未知来源({r[3]})"),
            "avg_duration": float(r[-4] or 0.0),
            "max_duration": int(r[-3] or 0),
            "min_duration": int(r[-2] or 0),
            "median_duration": float(r[-1] or 0.0),
        }
        if group_by_opponent:
            record.update({
                "opponent_class": r[4],
                "opponent_schools": r[5],
                "opponent_class_schools_name": get_class_school_name(r[4], r[5]),
            })
        rows.append(record)
    return {"data": rows}


@app.get("/api/export/csv")
def export_csv(
    metric: str = Query(..., description="winrate 或 duration"),
    servers: Optional[str] = None,
    start_ts: Optional[int] = None,
    end_ts: Optional[int] = None,
    min_level: Optional[int] = None,
    max_level: Optional[int] = None,
    clazz: Optional[int] = None,
    schools: Optional[int] = None,
    opponent_class: Optional[int] = None,
    opponent_schools: Optional[int] = None,
    spirit_animal: Optional[str] = None,
    spirit_animal_talents: Optional[int] = None,
    legendary_runes: Optional[str] = None,
    super_armor: Optional[int] = None,
    source_types: Optional[str] = None,
    sort: Optional[str] = None,
    group_by_opponent: bool = False,
    db: Session = Depends(get_db),
):
    metric = metric.lower()
    if metric == 'winrate':
        result = crud.query_winrate(
            db=db,
            group_by_opponent=group_by_opponent,
            servers=_parse_int_list(servers), start_ts=start_ts, end_ts=end_ts,
            min_level=min_level, max_level=max_level,
            clazz=clazz, schools=schools,
            opponent_class=opponent_class, opponent_schools=opponent_schools,
            spirit_animal=_parse_int_list(spirit_animal),
            spirit_animal_talents=spirit_animal_talents,
            legendary_runes=_parse_int_list(legendary_runes),
            super_armor=super_armor,
            source_types=_parse_int_list(source_types), sort=sort,
        )
        header = ["server", "class", "schools", "source_type"]
        if group_by_opponent:
            header += ["opponent_class", "opponent_schools"]
        header += ["win_count", "lose_count", "match_count", "win_rate"]
        rows = []
        for r in result:
            base = [r[0], r[1], r[2], r[3]]
            if group_by_opponent:
                base += [r[4], r[5]]
            base += [int(r[-4] or 0), int(r[-3] or 0), int(r[-2] or 0), float(r[-1] or 0.0)]
            rows.append(base)
    else:
        result = crud.query_duration(
            db=db,
            group_by_opponent=group_by_opponent,
            servers=_parse_int_list(servers), start_ts=start_ts, end_ts=end_ts,
            min_level=min_level, max_level=max_level,
            clazz=clazz, schools=schools,
            opponent_class=opponent_class, opponent_schools=opponent_schools,
            spirit_animal=_parse_int_list(spirit_animal),
            spirit_animal_talents=spirit_animal_talents,
            legendary_runes=_parse_int_list(legendary_runes),
            super_armor=super_armor,
            source_types=_parse_int_list(source_types), sort=sort,
        )
        header = ["server", "class", "schools", "source_type"]
        if group_by_opponent:
            header += ["opponent_class", "opponent_schools"]
        header += ["avg_duration", "max_duration", "min_duration", "median_duration"]
        rows = []
        for r in result:
            base = [r[0], r[1], r[2], r[3]]
            if group_by_opponent:
                base += [r[4], r[5]]
            base += [float(r[-4] or 0.0), int(r[-3] or 0), int(r[-2] or 0), float(r[-1] or 0.0)]
            rows.append(base)

    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(header)
    writer.writerows(rows)
    buf.seek(0)
    return StreamingResponse(iter([buf.getvalue()]), media_type="text/csv",
                             headers={"Content-Disposition": f"attachment; filename={metric}.csv"})



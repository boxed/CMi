from CMi import run_sql

def upgrade_1():
    run_sql('ALTER TABLE tvshows_show ADD COLUMN "auto_erase" bool NOT NULL DEFAULT 1')

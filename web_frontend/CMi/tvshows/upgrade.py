from CMi import run_sql

def upgrade_1():
    run_sql('ALTER TABLE tvshows_show ADD COLUMN "auto_erase" bool NOT NULL DEFAULT 1')

def upgrade_2():
    run_sql('ALTER TABLE tvshows_episode ADD COLUMN "watched_count" INTEGER default 0')
    run_sql('UPDATE tvshows_episode SET watched_count = watched')

-- UNSA Énergies national : tag régional sur les actualités
-- NULL = actualité nationale (toutes régions)
ALTER TABLE unsa_actus ADD COLUMN IF NOT EXISTS region TEXT DEFAULT NULL;


------------------------------------------------------------------------------------------------------------------
-- query che elimina i dati con accumulata > 3 mm e elimina i pluviometri con percentuale di errore < 30 %      --                                                                                                       
------------------------------------------------------------------------------------------------------------------

SELECT clean_gauge(3,30);
SELECT clean_peaks(3);


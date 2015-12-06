---------------------------------------- Query sui dati --------------------------------------------------------



/* CREATE VIEW rainfall_01_30 AS 
SELECT id_gauge, name, SUM(accumulated), location
FROM rain_gauge AS r, precipitation AS p
WHERE r.id_gauge = p.gauge AND
	date BETWEEN '2007-11-01' AND '2007-11-30'
GROUP BY r.id_gauge */

/* SELECT * 
FROM rainfall_01_30
WHERE sum =
	(SELECT MAX(sum) -- MIN(sum) 
	FROM rainfall_01_30) */

/* SELECT * 
FROM rainfall_01_30
WHERE sum > 200 */

/*SELECT AVG(sum)
FROM rainfall_01_30 */

-- DROP VIEW rainfall_01_30

/*SELECT *
FROM rain_gauge AS r, precipitation AS p
WHERE r.id_gauge = p.gauge AND
	r.name = 'Eur' AND
	p.date BETWEEN '2007-11-20' AND '2007-11-30' AND
	--p.time BETWEEN '00:00' AND '15:00'
	p.accumulated > 0
ORDER BY p.date, p.time */



---------------------------------------- Basic UDFs --------------------------------------------------------



-- SELECT import_precipitation('LucDanVit/dati/nome_file.dat', '2007-11-01'); -- importa i dati presenti su un file nel DB

-- SELECT clean_peaks(3); -- elimina valori di precipitazione rilevati maggiori di 3 mm

-- SELECT clean_gauge(3, 30); -- elimina i pluviometri con rilevazioni errate maggiori del 30%

-- SELECT * FROM rainGauges_filter('LAZIO', 10); -- filtra e seleziona i pluviometri situati all'interno di una regione alllargata con un boundary

-- SELECT average_minDistance('LAZIO'); -- calcola la media delle minime distanze tra tutti i pluviometri di una regione

-- SELECT max_minDistance('LAZIO'); -- calcola la massima tra le minime distanze tra tutti i pluviometri di una regione. 

-- SELECT rainGauges_density('LAZIO'); -- calcola la densità di distribuzione dei pluviometri in una data regione tramite la formula:
							--  densità = (numero di pluviometri)/(superficie della regione).



---------------------------------------- Drawing UDFs --------------------------------------------------------



-- calcola le somme progressive della pioggia accumulata ogni 15 minuti in un pluviometro in un intervallo di tempo e con questi dati crea un file pdf contenente un grafico

-- SELECT plot_withinHours('LucDanVit/grafici/plot_withinHours.pdf', 'Eur', '2007-11-01', '00:00', '23:00');

-- calcola le somme progressive della pioggia accumulata ogni 15 minuti in un pluviometro in un intervallo di giorni e con questi dati crea un file pdf contenente un grafico

-- SELECT plot_withinDays('LucDanVit/grafici/plot_withinDays.pdf', 'Eur', '2007-11-01', '2007-11-10');

-- crea un grafico, chiamato barplot, che mostra sull’asse delle x i pluviometri e sull’asse delle y la pioggia accumulata in ogni pluviometro in un intervallo di tempo

-- SELECT barPlot_withinHours('2007-11-01', '00:00', '23:00', 'LucDanVit/grafici/barPlot_withinHours.pdf');

-- crea un grafico, chiamato barplot, che mostra sull’asse delle x i pluviometri e sull’asse delle y la pioggia accumulata in ogni pluviometro in un intervallo di giorni

-- SELECT barPlot_withinDays('2007-11-01', '2007-11-30', 'LucDanVit/grafici/barPlot_withinDays.pdf');

-- prende come parametri una data e un intervallo orario e grafica la pioggia accumulata ogni 15 minuti e la somma progressiva relativa a quel periodo con due scale differenti 
-- sull'asse delle y (a sinistra la pioggia accumulata ogni 15 minuti e a destra la somma progressiva della pioggia accumulata).

-- SELECT rainfallPlot_withinHours('LucDanVit/grafici/rainfallPlot_withinHours.pdf', 'Eur', '2007-11-01', '00:00', '23:00'); 

-- prende come parametri un intervallo di date e grafica la pioggia accumulata ogni 15 minuti e la somma progressiva relativa a quel periodo con due scale differenti 
-- sull'asse delle y (a sinistra la pioggia accumulata ogni 15 minuti e a destra la somma progressiva della pioggia accumulata)

-- SELECT rainfallPlot_withinDays('LucDanVit/grafici/rainfallPlot_withinDays.pdf', 'Eur', '2007-11-20', '2007-11-30');

-- calcola la somma progressiva della pioggia accumulata ogni 15 minuti in un pluviometro in due intervalli di tempo e crea, 
-- con questi dati, due grafici affiancati salvandoli sullo stesso file

-- SELECT comparisonOfPlot_withinHours('LucDanVit/grafici/comparisonOfPlot_withinHours.pdf', 'Eur', '2007-11-10', '00:00', '23:00', '2007-11-11', '00:00', '23:00');

-- calcola la somma progressiva della pioggia accumulata ogni 15 minuti in un pluviometro in due intervalli di giorni e crea, 
-- con questi dati, due grafici affiancati salvandoli sullo stesso file

-- SELECT comparisonOfPlot_withinDays('LucDanVit/grafici/comparisonOfPlot_withinDays.pdf', 'Eur', '2007-11-01', '2007-11-05', '2007-11-06', '2007-11-10');

-- calcola la somma progressiva della pioggia accumulata ogni 15 minuti in due pluviometri nello stesso intervallo di tempo e crea, 
-- con questi dati, due grafici uno sotto l’altro salvandoli sullo stesso file

-- SELECT comparisonOfPlot_withinHours_betweenTwoRainGauges('LucDanVit/grafici/comparisonOfPlot_withinHours_betweenTwoRainGauges.pdf', 'Eur', 'Fondi', '2007-11-01', '00:00', '23:00');

-- calcola la somma progressiva della pioggia accumulata ogni 15 minuti in due pluviometri nello stesso intervallo di giorni e crea, 
-- con questi dati, due grafici uno sotto l’altro salvandoli sullo stesso file

-- SELECT comparisonOfPlot_withinDays_betweenTwoRainGauges('LucDanVit/grafici/comparisonOfPlot_withinDays_betweenTwoRainGauges.pdf', 'Eur', 'Fondi', '2007-11-01', '2007-11-10');



---------------------------------------- Interpolation UDFs --------------------------------------------------------


---------------------------------------- Simple Interpolation (griglia non filtrata) -------------------------------

-- Simple idw in hours

-- SELECT simpleidw_withinhours('2007-11-01', '00:00', '23:00', 'LucDanVit/interpolazione/simpleidw_withinhours.asc', 2.0, 1000, 1000);

-- Simple idw in Days

-- SELECT simpleidw_withindays('2007-11-01', '2007-11-02', 'LucDanVit/interpolazione/simpleidw_withindays.asc', 2, 1000, 1000);

-- Simple kriging in hours

-- SELECT simplekriging_withinhours('2007-11-01', '00:00', '23:00', 'LucDanVit/interpolazione/simplekriging_withinhours.asc', 2.0, 1000, 1000);

-- Simple kriging in days

-- SELECT simplekriging_withindays('2007-11-01', '2007-11-02', 'LucDanVit/interpolazione/simplekriging_withindays.asc', 2, 1000, 1000);

---------------------------------------- IDW --------------------------------------------------------

-- esegue l'interpolazione tramite tecnica IDW della pioggia accumulata in un intervallo orario. Il power permette di scegliere il valore di potenza 
-- con cui compiere l’interpolazione. Infine crea un file raster .asc

-- SELECT idw_withinhours('LAZIO', '2007-11-01', '00:00', '23:00', 'LucDanVit/interpolazione/idw_whithinHours.asc', 2.0, 300, 300);

-- esegue l'interpolazione tramite tecnica IDW della pioggia accumulata in un intervallo di giorni. Il power permette di scegliere il valore di potenza 
-- con cui compiere l’interpolazione. Infine crea un file raster .asc.

-- SELECT idw_withinDays('LAZIO', '2007-11-01', '2007-11-02', 'LucDanVit/interpolazione/idw_whithinDays.asc', 2, 50, 50);

---------------------------------------- Kriging --------------------------------------------------------

-- esegue l'interpolazione tramite tecnica kriging della pioggia accumulata in un dato intervallo di giorni. Il cut permette di scegliere il valore di cutoff 
-- con cui compiere l’interpolazione. Infine crea un file raster .asc

-- SELECT kriging_withinhours('LAZIO', '2007-11-01', '00:00', '23:00', 'LucDanVit/interpolazione/kriging_withinhours.asc', 2, 50, 50);

-- esegue l'interpolazione tramite tecnica kriging della pioggia accumulata in un dato intervallo di ore. Il cut permette di scegliere il valore di cutoff 
-- con cui compiere l’interpolazione. Infine crea un file raster .asc

-- SELECT kriging_withindays('LAZIO', '2007-11-01', '2007-11-02', 'LucDanVit/interpolazione/kriging_withindays.asc', 2, 50, 50);

-- esegue l'interpolazione tramite tecnica kriging, ponendo i valori negativi a NA, della pioggia accumulata in un dato intervallo di ore. Il cut permette di scegliere il 
-- valore di cutoff con cui compiere l’interpolazione. Infine crea un file raster .asc

-- SELECT nakriging_withinhours('LAZIO', '2007-11-01', '00:00', '23:00', 'LucDanVit/interpolazione/nakriging_withinhours.asc', 2, 50, 50);

-- esegue l'interpolazione tramite tecnica kriging, ponendo i valori negativi a NA, della pioggia accumulata in un dato intervallo di giorni. Il cut permette di scegliere il 
-- valore di cutoff con cui compiere l’interpolazione. Infine crea un file raster .asc

-- SELECT nakriging_withindays('LAZIO', '2007-11-01', '2007-11-02', 'LucDanVit/interpolazione/nakriging_withindays.asc', 2, 50, 50);

-- esegue l'interpolazione tramite tecnica kriging, ponendo i valori negativi a zero, della pioggia accumulata in un dato intervallo di ore. Il cut permette di scegliere il 
-- valore di cutoff con cui compiere l’interpolazione. Infine crea un file raster .asc.

-- SELECT zerokriging_withinhours('LAZIO', '2007-11-01', '00:00', '23:00', 'LucDanVit/interpolazione/zerokriging_withinhours.asc', 2, 50, 50);

-- esegue l'interpolazione tramite tecnica kriging, ponendo i valori negativi a zero, della pioggia accumulata in un dato intervallo di giorni. Il cut permette di scegliere il 
-- valore di cutoff con cui compiere l’interpolazione. Infine crea un file raster .asc

-- SELECT zerokriging_withindays('LAZIO', '2007-11-01', '2007-11-02', 'LucDanVit/interpolazione/zerokriging_withindays.asc', 2, 50, 50);

-- esegue l'interpolazione tramite tecnica kriging, eseguendo una trasformazione logaritmica del campo, della pioggia accumulata in un dato intervallo di ore. Il cut permette di 
-- scegliere il valore di cutoff con cui compiere l’interpolazione. Infine crea un file raster .asc.

-- SELECT logarithmickriging_withinhours('LAZIO', '2007-11-01', '00:00', '23:00', 'LucDanVit/interpolazione/logarithmickriging_withinhours.asc', 2, 50, 50);

-- esegue l'interpolazione tramite tecnica kriging, eseguendo una trasformazione logaritmica del campo, della pioggia accumulata in un dato intervallo di giorni. Il cut permette 
-- di scegliere il valore di cutoff con cui compiere l’interpolazione. Infine crea un file raster .asc

-- SELECT logarithmickriging_withindays('LAZIO', '2007-11-01', '2007-11-02', 'LucDanVit/interpolazione/logarithmickriging_withindays.asc', 2, 50, 50);



---------------------------------------- Cross Validation UDFs --------------------------------------------------------


---------------------------------------- IDW --------------------------------------------------------

-- calcola gli errori quadratici medi relativi a interpolazioni IDW compiute cambiando il valore di potenza. Le interpolazioni sono tutte riferite 
-- allo stesso intervallo di tempo passato come parametro

-- SELECT * FROM idw_crossvalidation_withinhours('2007-11-01', '00:00', '23:00', 1, 5, 1);

-- calcola gli errori quadratici medi relativi a interpolazioni idw compiute cambiando il valore di potenza. Le interpolazioni sono tutte riferite 
-- allo stesso intervallo di giorni passato come parametro

-- SELECT * FROM idw_crossvalidation_withindays('2007-11-01', '2007-11-05', 1, 5, 1);

---------------------------------------- Kriging --------------------------------------------------------

-- calcola gli errori quadratici medi relativi a interpolazioni kriging compiute cambiando il valore di cutoff. Le interpolazioni sono tutte riferite 
-- allo stesso intervallo di ore passato come parametro

-- SELECT * FROM kriging_crossvalidation_withinhours('2007-11-01', '00:00', '23:00', 1, 5, 1);

-- calcola gli errori quadratici medi relativi a interpolazioni kriging compiute cambiando il valore di cutoff. Le interpolazioni sono tutte riferite 
-- allo stesso intervallo di giorni passato come parametro

-- SELECT * FROM kriging_crossvalidation_withindays('2007-11-01', '2007-11-10', 1, 5, 1);

-- calcola gli errori quadratici medi relativi a interpolazioni kriging, eseguendo una trasformazione logaritmica del campo, compiute cambiando il valore di cutoff. 
-- Le interpolazioni sono tutte riferite allo stesso intervallo di ore passato come parametro

-- SELECT * FROM logarithmickriging_crossvalidation_withinhours('2007-11-01', '00:00', '23:00', 1, 5, 1);

-- calcola gli errori quadratici medi relativi a interpolazioni kriging, eseguendo una trasformazione logaritmica del campo, compiute cambiando il valore di cutoff. 
-- Le interpolazioni sono tutte riferite allo stesso intervallo di giorni passato come parametro

-- SELECT * FROM logarithmickriging_crossvalidation_withindays('2007-11-01', '2007-11-10', 1, 5, 1);






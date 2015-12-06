-------------------------------------------
-- creazione del tipo di dato rainfall   --
-------------------------------------------

CREATE TYPE rainfall AS
   (date date,
    time time without time zone,
    sum double precision);

--------------------------------------------------
-- creazione del tipo di dato rainfall_location --
--------------------------------------------------
  
CREATE TYPE rainfall_location AS
   (id_gauge integer,
    gauge_name character varying(50),
    location geometry,
    sum double precision);

-----------------------------------------------
-- creazione del tipo di dato rainfallPlus  --                                                                                           
-----------------------------------------------

CREATE TYPE rainfallPlus AS
   (date date,
    time time without time zone,
    rain double precision,
    sum double precision);

-----------------------------------------------------------------------------------------------------------
-- funzione che mette a NULL i valori di accumulated della tabella precipitation sopra una certa soglia  --                                                                                                       
-----------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION clean_peaks(threshold double precision)
  RETURNS void AS
$BODY$

	UPDATE precipitation SET accumulated = NULL WHERE accumulated > threshold;

$BODY$
  LANGUAGE SQL;

---------------------------------------------------------------------------------------------------------------------
-- funzione che elimina i pluviometri per i quali la percentuale di rilevazioni errate supera una percentuale data --                                                                                                       
---------------------------------------------------------------------------------------------------------------------
  
CREATE OR REPLACE FUNCTION clean_gauge(threshold double precision, percentage double precision) 
RETURNS SETOF boolean AS
$BODY$
DECLARE
	c1 double precision;
	c2 double precision;
	p double precision;
	row rain_gauge%rowtype;
BEGIN

FOR row IN SELECT * FROM rain_gauge
	LOOP
		SELECT count(*) 
		FROM rain_gauge, precipitation 
		WHERE rain_gauge.id_gauge = precipitation.gauge AND 
			rain_gauge.name = row.name AND 
			precipitation.accumulated >= threshold
		INTO c1;
		
		SELECT count(*) 
		FROM rain_gauge, precipitation 
		WHERE rain_gauge.id_gauge = precipitation.gauge AND 
			rain_gauge.name = row.name AND
			precipitation.accumulated IS NOT NULL
		INTO c2;
		IF c2 != 0 THEN
			p := c1/c2*100;

			IF p > percentage THEN 
				DELETE FROM precipitation WHERE gauge = row.id_gauge;
				DELETE FROM rain_gauge WHERE name = row.name;
				RETURN NEXT TRUE;
			ELSE 
				RETURN NEXT FALSE;
			END IF;
		ELSE 
			RETURN NEXT FALSE;
		END IF;
	END LOOP;
END;
$BODY$ LANGUAGE 'plpgsql';

------------------------------------------------------------------------------------------------------------------
-- funzione che filtra i pluviometri in base alla regione il cui confine può essere allargato con tramite bound --                                                                                                       
------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION rainGauges_filter(region_name text, bound double precision) 
  RETURNS SETOF rain_gauge AS $BODY$

	SELECT r2.*
	FROM region AS r1, rain_gauge AS r2
	WHERE r1.name = UPPER(region_name) AND 
		ST_Contains(ST_Buffer(r1.boundary, bound/100), r2.location) = 'true'

$BODY$ LANGUAGE SQL;

--------------------------------------------------------------------------------------------------------------
-- funzione che calcola tra tutte le distanze minime di ogni pluviometro rispetto agli altri, la loro media --                                                                                                       
--------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION average_minDistance(region_name text)
  RETURNS double precision AS
$BODY$
DECLARE
	r double precision;
	tot double precision;
	z integer;
	id integer;
BEGIN
	z = 1;
	tot = 0;
	FOR id IN SELECT id_gauge 
		FROM rain_gauge, region 
		WHERE region.name = UPPER(region_name) 
			AND ST_Contains(region.boundary, rain_gauge.location) = 'true'
	LOOP
		FOR r IN SELECT min(ST_Distance(r1.location, r2.location))*100
			FROM rain_gauge AS r1, rain_gauge AS r2
			WHERE r1.id_gauge != r2.id_gauge AND 
			r1.id_gauge = id 
		LOOP
			tot = tot + r;
		END LOOP;
		z = z + 1;
	END LOOP;
	RETURN tot/(z - 1);
END;
$BODY$
  LANGUAGE 'plpgsql';

---------------------------------------------------------------------------------------------------------------
-- funzione che calcola tra tutte le distanze minime di ogni pluviometro rispetto agli altri, quella massima --                                                                                                       
---------------------------------------------------------------------------------------------------------------
  
CREATE OR REPLACE FUNCTION max_minDistance(region_name text)
  RETURNS double precision AS
$BODY$
DECLARE
	r double precision;
	tot double precision;
	id integer;
BEGIN
	tot = 0;
	FOR id IN SELECT id_gauge 
		FROM rain_gauge, region 
		WHERE region.name = UPPER(region_name) 
			AND ST_Contains(region.boundary, rain_gauge.location) = 'true'
	LOOP
		FOR r IN SELECT min(ST_Distance(r1.location, r2.location))*100
			FROM rain_gauge AS r1, rain_gauge AS r2
			WHERE r1.id_gauge != r2.id_gauge AND 
			r1.id_gauge = id 
		LOOP
			IF(r>tot)THEN tot = r;
			END IF;
		END LOOP;
	END LOOP;
	RETURN tot;
END;
$BODY$
  LANGUAGE 'plpgsql';

-------------------------------------------------------------------------------------------
--  funzione che restituisce la densità dei pluviometri presenti in una regione italiana --                                                                                                      
-------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION rainGauges_density(region_name text)
  RETURNS double precision AS
$BODY$
DECLARE
	tot_rain integer;
	area_reg double precision;
	density double precision;
BEGIN
	tot_rain = (SELECT count(*) 
			FROM rainGauges_filter(UPPER(region_name), 0));
	area_reg = (SELECT st_area(geography(ST_Transform(boundary,4326)))
			FROM region
			WHERE name = UPPER(region_name));

		density = tot_rain/(area_reg/1000000);

	RETURN density;
END;
$BODY$
  LANGUAGE 'plpgsql';

-------------------------------------------------------------------------------------------------------------------
-- funzione che dati il nome di una stazione, una data e un intervallo di tempo calcola la somma delle rainfall  --                                                                                                       
-------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_1(gauge_name text, day text, from_h text, to_h text) 
RETURNS SETOF rainfall AS
$BODY$
DECLARE 
	row precipitation%rowtype;
	result rainfall;
BEGIN
	result.sum = 0;
	FOR row IN SELECT *
		FROM precipitation AS d, rain_gauge AS r 
		WHERE r.id_gauge = d.gauge AND  
		      r.name = gauge_name AND 
		      d.date = CAST(day as date) AND
		      d.time BETWEEN CAST(from_h as time) AND CAST(to_h as time)
		ORDER BY d.time
	LOOP
		result.date = row.date;
		result.time = row.time;
		IF row.accumulated IS NOT NULL THEN 
			result.sum = result.sum + row.accumulated;
		ELSE
			result.sum = result.sum;
		END IF;
		RETURN NEXT result;
	END LOOP;
	RETURN;
END
$BODY$ LANGUAGE 'plpgsql';

---------------------------------------------------------------------------------------------------------
-- funzione che dati il nome di una stazione e un intervallo di date calcola la somma delle rainfall   --                                                                                                       
---------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_2(gauge_name text, from_d text, to_d text)
RETURNS SETOF rainfall AS
$BODY$
DECLARE 
	row precipitation%rowtype;
	result rainfall;
	d date;
BEGIN
	result.sum = 0;
	result.date = '3000-12-31';
	FOR row IN SELECT *
		FROM precipitation AS d, rain_gauge AS r 
		WHERE r.id_gauge = d.gauge AND  
		      r.name = gauge_name AND
		      d.date BETWEEN CAST(from_d as date) AND CAST(to_d as date)
		ORDER BY d.date
	LOOP 
		d = result.date;
		result.date = row.date;
		IF row.accumulated IS NOT NULL THEN 
			
			result.sum = result.sum + row.accumulated;
		ELSE
			result.sum = result.sum;
		END IF;
		IF row.date != d THEN 
			RETURN NEXT result;
		END IF;
	END LOOP;
	RETURN;
END
$BODY$
  LANGUAGE 'plpgsql';

----------------------------------------------------------------------------------------------------------------------
-- funzione che dato un giorno e un intervallo di ore ritorna la somma totale delle accumulate di ogni pluviometro  --                                                                                                       
----------------------------------------------------------------------------------------------------------------------
	
CREATE OR REPLACE FUNCTION UDF_3(day text, from_h text, to_h text)
RETURNS SETOF rainfall_location AS
$BODY$
DECLARE 
	row rainfall_location;
BEGIN
	FOR row IN SELECT r.id_gauge, r.name, r.location, SUM(d.accumulated)
		FROM rain_gauge AS r, precipitation AS d
		WHERE r.id_gauge = d.gauge 
			AND d.date = CAST(day as date) 
			AND d.time BETWEEN CAST(from_h as time) AND CAST(to_h as time)	
			GROUP BY r.id_gauge		
	LOOP
		RETURN NEXT row;
	END LOOP;
END;
$BODY$
  LANGUAGE 'plpgsql';

--------------------------------------------------------------------------------------------------------------
--  funzione che dato un intervallo di giorni ritorna la somma totale delle accumulate di ogni pluviometro  --                                                                                                     
--------------------------------------------------------------------------------------------------------------
  
CREATE OR REPLACE FUNCTION UDF_4(from_d text, to_d text)
  RETURNS SETOF rainfall_location AS
$BODY$
DECLARE 
	row rainfall_location;
BEGIN
	FOR row IN SELECT r.id_gauge, r.name, r.location, SUM(d.accumulated)
		FROM rain_gauge AS r, precipitation AS d
		WHERE r.id_gauge = d.gauge AND 
			d.date BETWEEN CAST(from_d AS date) AND CAST(to_d AS date)		
			GROUP BY r.id_gauge		
	LOOP
		RETURN NEXT row;
	END LOOP;
END;
$BODY$
  LANGUAGE 'plpgsql';
  
--------------------------------------------------------------------------------------------------------------
-- rain_in_hours                                                                                                     
--------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_5(gauge_name text, day text, from_h text, to_h text)
  RETURNS SETOF rainfallPlus AS
$BODY$
DECLARE
	row precipitation%rowtype;
	result rainfallPlus;
BEGIN
	result.sum = 0;
	FOR row IN SELECT *
		FROM precipitation AS d, rain_gauge AS r 
		WHERE r.id_gauge = d.gauge AND  
		      r.name = gauge_name AND 
		      d.date = CAST(day as date) AND
		      d.time BETWEEN CAST(from_h as time) AND CAST(to_h as time)
		ORDER BY d.time
	LOOP 
		result.date = row.date;
		result.time = row.time;
		IF row.accumulated IS NOT NULL THEN 
			result.rain = row.accumulated;
			result.sum = result.sum + row.accumulated;
		ELSE
			result.rain = 0;
			result.sum = result.sum;
		END IF;
		RETURN NEXT result;
	END LOOP;
	RETURN;
END
$BODY$
  LANGUAGE 'plpgsql';

--------------------------------------------------------------------------------------------------------------
-- rain_plot                                                                                                    
--------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_6(path text, gauge_name text, date text, x1 time without time zone[], y double precision[], s double precision[])
  RETURNS boolean AS
$BODY$

	x2 <- strptime(x1, format = '%H:%M');
	x <- as.double(x2);
	l <- length(x);
	pdf(path);
	barplot(y, xlab = 'Time (LT) [hh-mm-ss]', ylab = 'Rainfall [mm]', main = paste('Rainfall at ', gauge_name, ' on ', date, ' rain gauge'), xaxt = 'n');
	par (new = T);
	plot(x, s, type = 'l', yaxt = 'n', xaxt = 'n', xlab = '', ylab = '', col ='blue', lwd = 2);
	axis(1, at = c(x[1], x[l/4], x[l/2], x[(3*l)/4], x[l]), labels = c(x1[1], x1[l/4], x1[l/2], x1[(3*l)/4], x1[l]));
	axis(4);
	legend("topleft", 'Zigzag Curve', lty= 1, pch= -1, col= 'blue', lwd= 2);
	dev.off();
	return (TRUE);

$BODY$
  LANGUAGE 'plr';

--------------------------------------------------------------------------------------------------------------
-- rain_plot_in_hours                                                                                                       
--------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION rainfallPlot_withinHours(path text, gauge_name text, day text, from_h text, to_h text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfallPlus;
	x time[];
	y double precision[];
	s double precision[];
	i integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_5(gauge_name, day, from_h, to_h)
	LOOP 
		x[i] = r.time;
		y[i] = r.rain;
		s[i] = r.sum;
		i = i + 1;
	END LOOP;
	RETURN UDF_6(path, gauge_name, day, x, y, s);
END
$BODY$
  LANGUAGE 'plpgsql';

--------------------------------------------------------------------------------------------------------------
-- funzione che esegue il plot completo dei dati specificati da x1 e y in un file pdf specificato in path   --                                                                                                       
--------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_7(path text, gauge_name text, x1 time without time zone[], y double precision[])
  RETURNS boolean AS
$BODY$

	x2 <- strptime(x1, format = '%H:%M');
	x <- as.double(x2);
	l <- length(x);
	pdf(path);
	plot(x,y, xlab = 'Time (LT) [hh-mm-ss]', ylab = 'Rainfall [mm]', main = paste('Rainfall at ', gauge_name, ' rain gauge'), xaxt = 'n');
	axis(1, at = c(x[1], x[l/2],x[l]), labels = c(x1[1], x1[l/2], x1[l]));
	lines(x, y, col = 'blue', lwd = 2);
	legend("topleft", c('Rainfall Value','Zigzag Curve'), lty=c(-1,1), pch=c(1,-1), col=c('black','blue'), lwd=c(-1,2), merge =TRUE);
	dev.off();
	return (TRUE);

$BODY$
  LANGUAGE 'plr'; 

--------------------------------------------------------------------------------------------------------------
-- funzione che esegue il plot completo dei dati specificati da x1 e y in un file pdf specificato in path   --                                                                                                       
--------------------------------------------------------------------------------------------------------------
  
CREATE OR REPLACE FUNCTION UDF_8(path text, gauge_name text, x1 date[], y double precision[])
  RETURNS boolean AS
$BODY$


	x2 <- as.Date(x1, format = '%Y-%m-%d');
	x <- as.double(x2);
	l <- length(x);
	pdf(path);
	plot(x,y, xlab = 'Date [yyyy-mm-dd]', ylab = 'Rainfall [mm]', main = paste('Rainfall at ', gauge_name, ' rain gauge'), xaxt = 'n');
	axis(1, at = c(x[1], x[l/2],x[l]), labels = c(x1[1], x1[l/2], x1[l]));
	lines(x, y, col = 'blue', lwd = 2); 
	legend("topleft", c('Rainfall Value','Zigzag Curve'), lty=c(-1,1), pch=c(1,-1), col=c('black','blue'), lwd=c(-1,2), merge =TRUE);
	dev.off();
	return (TRUE);

$BODY$
  LANGUAGE 'plr';

-------------------------------------------------------------------------------------------------------------------------------
-- funzione che esegue il plot completo dei dati presi dalla funzione UDF_1 in un file pdf specificato in path --                                                                                                       
-------------------------------------------------------------------------------------------------------------------------------
  
CREATE OR REPLACE FUNCTION plot_withinHours(path text, gauge_name text, day text, from_h text, to_h text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfall;
	x time[];
	y double precision[];
	i integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_1(gauge_name, day, from_h, to_h)
	LOOP 
		x[i] = r.time;
		y[i] = r.sum;
		i = i + 1;
	END LOOP;
	RETURN UDF_7(path, gauge_name, x, y);
END
$BODY$
  LANGUAGE 'plpgsql';

--------------------------------------------------------------------------------------------------------------
-- funzione che esegue il plot completo dei dati presi dalla funzione UDF_2 in un file pdf specificato in path --                                                                                                       
--------------------------------------------------------------------------------------------------------------
  
CREATE OR REPLACE FUNCTION plot_withinDays(path text, gauge_name text, from_d text, to_d text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfall;
	x date[];
	y double precision[];
	i integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_2(gauge_name, from_d, to_d)
	LOOP 
		x[i] = r.date;
		y[i] = r.sum;
		i = i + 1;
	END LOOP;
	RETURN UDF_8(path, gauge_name, x, y);
END
$BODY$
  LANGUAGE 'plpgsql';

-------------------------------------------------------------------------------------------------------------
--                                                                                                        
--------------------------------------------------------------------------------------------------------------
      
CREATE OR REPLACE FUNCTION UDF_9(acc double precision[], path text, date date, from_h text, to_h text)
  RETURNS boolean AS
$BODY$
pdf(path)
barplot(acc, main= paste("Rainfall at all rain gauges on ", date, "\n from ", from_h, " to ", to_h, " (LT)"), xlab = 'Rain gauges', ylab = 'Rainfall [mm]')
dev.off()
return(TRUE);
$BODY$
  LANGUAGE 'plr';

--------------------------------------------------------------------------------------------------------------
--                                                                                                        
--------------------------------------------------------------------------------------------------------------
  
CREATE OR REPLACE FUNCTION barPlot_withinHours(dat date, from_h text, to_h text, path text)
  RETURNS boolean AS
$BODY$
DECLARE
	r record;
	acc double precision[];
	i integer = 1;
BEGIN

	FOR r IN SELECT SUM(accumulated) AS acc FROM precipitation AS d 
			WHERE d.date = dat 
			AND d.time > CAST (from_h AS time) 
			AND d.time < CAST (to_h AS time) 
			GROUP BY d.gauge
	LOOP
		acc[i] = r.acc;
		i = i + 1;
	END LOOP;
	RETURN UDF_9(acc, path, dat, from_h, to_h);
END;
$BODY$
LANGUAGE 'plpgsql';

--------------------------------------------------------------------------------------------------------------
--                                                                                                        
--------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_10(path text, gauge_name text, date1 text, t1 time without time zone[], acc1 double precision[], date2 text, t2 time without time zone[], acc2 double precision[])
  RETURNS boolean AS
$BODY$

	x1 <- strptime(t1, format = '%H:%M');
	x <- as.double(x1);
	l <- length(x);
	x2 <- strptime(t2, format = '%H:%M');
	c <- as.double(x2);
	l2 <- length(x);
	m <- max (acc1,acc2);
	
	pdf(path);
	attach(mtcars)
	par(mfrow=c(1,2))
	
	plot(x,acc1, xlab = 'Time (LT) [hh-mm-ss]', ylab = 'Rainfall [mm]', ylim=c(0,m), 
			main = paste('Rainfall at ', gauge_name, ' rain gauge ', '\n on ', date1), 
			xaxt = 'n', yaxt = 'n');
			
	axis(1, at = c(x[1], x[l/2],x[l]), labels = c(t1[1], t1[l/2], t1[l]));
	axis(2, at = c(0, m/2, m), labels = c(0, m/2, m));
	lines(x, acc1, col = 'blue', lwd = 2);
	
	legend("topleft", c('Rainfall Value','Zigzag Curve'), lty=c(-1,1), pch=c(1,-1), col=c('black','blue'), 
			lwd=c(-1,2), merge =TRUE);

	plot(c,acc2, xlab = 'Time (LT) [hh-mm-ss]', ylab = 'Rainfall [mm]', ylim=c(0,m), 
			main = paste('Rainfall at ', gauge_name, ' rain gauge ', '\n on ', date2), 
			xaxt = 'n', yaxt = 'n');
			
	axis(1, at = c(c[1], c[l2/2],c[l2]), labels = c(t2[1], t2[l2/2], t2[l2]));
	axis(2, at = c(0, m/2, m), labels = c(0, m/2, m));
	lines(c, acc2, col = 'blue', lwd = 2);
	legend("topleft", c('Rainfall Value','Zigzag Curve'), lty=c(-1,1), pch=c(1,-1), 
			col=c('black','blue'), lwd=c(-1,2), merge =TRUE);
	dev.off();
	return (TRUE);

$BODY$
  LANGUAGE 'plr'; 

--------------------------------------------------------------------------------------------------------------
--                                                                                                        
--------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION comparisonOfPlot_withinHours(path text, gauge_name text, day1 text, 
		from_h text, to_h text, day2 text, from_h2 text, to_h2 text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfall;
	r1 rainfall;
	x1 time without time zone[];
	x2 time without time zone[];
	y1 double precision[];
	y2 double precision[];
	i integer = 1;
	j integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_1(gauge_name, day1, from_h, to_h)
	LOOP 
		x1[i] = r.time;
		y1[i] = r.sum;
		i = i + 1;
	END LOOP;
	
	FOR r1 IN SELECT *
		FROM UDF_1(gauge_name, day2, from_h2, to_h2)
	LOOP 
		x2[j] = r1.time;
		y2[j] = r1.sum;
		j = j + 1;
	END LOOP;
	RETURN UDF_10(path, gauge_name, day1, x1, y1, day2, x2, y2);
END
$BODY$
  LANGUAGE 'plpgsql';

--------------------------------------------------------------------------------------------------------------
--                                                                                                        
--------------------------------------------------------------------------------------------------------------
  
CREATE OR REPLACE FUNCTION UDF_11(path text, gauge_name text, d1 date[], acc1 double precision[], d2 date[], acc2 double precision[])
  RETURNS boolean AS
$BODY$


	x1 <- as.Date(d1, format = '%Y-%m-%d');
	x <- as.double(x1);
	l <- length(x);
	x2 <- as.Date(d2, format = '%Y-%m-%d');
	c <- as.double(x2);
	l2 <- length(x);
	m <- max (acc1,acc2);
	
	pdf(path);
	attach(mtcars)
	par(mfrow=c(1,2))
	
	plot(x,acc1, xlab = 'Date [yyyy-mm-dd]', ylab = 'Rainfall [mm]', ylim=c(0,m+m/4), 
			main = paste('Rainfall at ', gauge_name, ' rain gauge'), xaxt = 'n', yaxt = 'n');
	axis(1, at = c(x[1], x[l/2],x[l]), labels = c(d1[1], d1[l/2], d1[l]));
	axis(2, at = c(0, m/2, m), labels = c(0, m/2, m));
	lines(x, acc1, col = 'blue', lwd = 2);
	
	legend("topleft", c('Rainfall Value','Zigzag Curve'), lty=c(-1,1), pch=c(1,-1), 
			col=c('black','blue'), lwd=c(-1,2), merge =TRUE);

	plot(c,acc2, xlab = 'Date [yyyy-mm-dd]', ylab = 'Rainfall [mm]', ylim=c(0,m+m/4), 
			main = paste('Rainfall at ', gauge_name, ' rain gauge'), xaxt = 'n', yaxt = 'n');
			
	axis(1, at = c(c[1], c[l2/2],c[l2]), labels = c(d2[1], d2[l2/2], d2[l2]));
	axis(2, at = c(0, m/2, m), labels = c(0, m/2, m));
	lines(c, acc2, col = 'blue', lwd = 2);
	
	legend("topleft", c('Rainfall Value','Zigzag Curve'), lty=c(-1,1), pch=c(1,-1), 
			col=c('black','blue'), lwd=c(-1,2), merge =TRUE);
			
	dev.off();
	return (TRUE);

$BODY$
  LANGUAGE 'plr';

--------------------------------------------------------------------------------------------------------------
--                                                                                                        
--------------------------------------------------------------------------------------------------------------
  
CREATE OR REPLACE FUNCTION comparisonOfPlot_withinDays(path text, gauge_name text, 
		from_d text, to_d text, from_d2 text, to_d2 text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfall;
	r1 rainfall;
	x1 date[];
	x2 date[];
	y1 double precision[];
	y2 double precision[];
	i integer = 1;
	j integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_2(gauge_name, from_d, to_d)
	LOOP 
		x1[i] = r.date;
		y1[i] = r.sum;
		i = i + 1;
	END LOOP;
	
	FOR r1 IN SELECT *
		FROM UDF_2(gauge_name, from_d2, to_d2)
	LOOP 
		x2[j] = r1.date;
		y2[j] = r1.sum;
		j = j + 1;
	END LOOP;
	RETURN UDF_11(path, gauge_name, x1, y1, x2, y2);
END
$BODY$
  LANGUAGE 'plpgsql';

--------------------------------------------------------------------------------------------------------------
--                                                                                                        
--------------------------------------------------------------------------------------------------------------
  
CREATE OR REPLACE FUNCTION UDF_12(path text, gauge_name1 text, gauge_name2 text, t1 time without time zone[], acc1 double precision[], t2 time without time zone[], acc2 double precision[])
  RETURNS boolean AS
$BODY$

	x1 <- strptime(t1, format = '%H:%M');
	x <- as.double(x1);
	l <- length(x);
	x2 <- strptime(t2, format = '%H:%M');
	c <- as.double(x2);
	l2 <- length(x);
	pdf(path);
	attach(mtcars)
	par(mfrow=c(2,1))
	plot(x, acc1, xlab = 'Time (LT) [hh-mm-ss]', ylab = 'Rainfall [mm]',  pch=20, main = paste('Rainfall at ', gauge_name1, ' rain gauge'), xaxt = 'n');
	axis(1, at = c(x[1], x[l/2],x[l]), labels = c(t1[1], t1[l/2], t1[l]));
	lines(x, acc1, col = 'blue', lwd = 2);
	legend("topleft", c('Rainfall Value','Zigzag Curve'), lty=c(-1,1), pch=c(20,-1), col=c('black','blue'), lwd=c(-1,2), merge =TRUE);

	plot(c,acc2, xlab = 'Time (LT) [hh-mm-ss]', ylab = 'Rainfall [mm]',  pch=20, main = paste('Rainfall at ', gauge_name2, ' rain gauge'), xaxt = 'n');
	axis(1, at = c(c[1], c[l2/2],c[l2]), labels = c(t2[1], t2[l2/2], t2[l2]));
	lines(c, acc2, col = 'blue', lwd = 2);
	legend("topleft", c('Rainfall Value','Zigzag Curve'), lty=c(-1,1), pch=c(20,-1), col=c('black','blue'), lwd=c(-1,2), merge =TRUE);

	dev.off();
	return (TRUE);

$BODY$
  LANGUAGE 'plr';

--------------------------------------------------------------------------------------------------------------
--                                                                                                        
--------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION comparisonOfPlot_withinHours_betweenTwoRainGauges(path text, 
		gauge_name1 text, gauge_name2 text, day text,
		from_h text, to_h text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfall;
	r1 rainfall;
	x1 time[];
	x2 time[];
	y1 double precision[];
	y2 double precision[];
	i integer = 1;
	j integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_1(gauge_name1, day, from_h, to_h)
	LOOP 
		x1[i] = r.time;
		y1[i] = r.sum;
		i = i + 1;
	END LOOP;
	
	FOR r1 IN SELECT *
		FROM UDF_1(gauge_name2, day, from_h, to_h)
	LOOP 
		x2[j] = r1.time;
		y2[j] = r1.sum;
		j = j + 1;
	END LOOP;
	RETURN UDF_12(path, gauge_name1, gauge_name2, 
			x1, y1, x2, y2);
END
$BODY$
  LANGUAGE 'plpgsql';

--------------------------------------------------------------------------------------------------------------
--                                                                                                        
--------------------------------------------------------------------------------------------------------------
  
CREATE OR REPLACE FUNCTION UDF_13(path text, gauge_name1 text, gauge_name2 text, d1 date[], acc1 double precision[], d2 date[], acc2 double precision[])
  RETURNS boolean AS
$BODY$


	x1 <- as.Date(d1, format = '%Y-%m-%d');
	x <- as.double(x1);
	l <- length(x);
	x2 <- as.Date(d2, format = '%Y-%m-%d');
	c <- as.double(x2);
	l2 <- length(x);
	pdf(path);
	attach(mtcars)
	par(mfrow=c(2,1))
	
	plot(x,acc1, xlab = 'Date [yyyy-mm-dd]', ylab = 'Rainfall [mm]', 
			main = paste('Rainfall at ', gauge_name1, ' rain gauge'), xaxt = 'n');
			
	axis(1, at = c(x[1], x[l/2],x[l]), labels = c(d1[1], d1[l/2], d1[l]));
	lines(x, acc1, col = 'blue', lwd = 2);
	
	legend("topleft", c('Rainfall Value','Zigzag Curve'), lty=c(-1,1), 
			pch=c(1,-1), col=c('black','blue'), lwd=c(-1,2), merge =TRUE);
	
	plot(c,acc2, xlab = 'Date [yyyy-mm-dd]', ylab = 'Rainfall [mm]', 
			main = paste('Rainfall at ', gauge_name2, ' rain gauge'), xaxt = 'n');
			
	axis(1, at = c(c[1], c[l2/2],c[l2]), labels = c(d2[1], d2[l2/2], d2[l2]));
	lines(c, acc2, col = 'blue', lwd = 2);
	
	legend("topleft", c('Rainfall Value','Zigzag Curve'), lty=c(-1,1), 
			pch=c(1,-1), col=c('black','blue'), lwd=c(-1,2), merge =TRUE);
			
	dev.off();
	return (TRUE);

$BODY$
  LANGUAGE 'plr';

--------------------------------------------------------------------------------------------------------------
--                                                                                                        
--------------------------------------------------------------------------------------------------------------
  
CREATE OR REPLACE FUNCTION comparisonOfPlot_withinDays_betweenTwoRainGauges(path text, gauge_name1 text, 
		gauge_name2 text, from_d text, to_d text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfall;
	r1 rainfall;
	x1 date[];
	x2 date[];
	y1 double precision[];
	y2 double precision[];
	i integer = 1;
	j integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_2(gauge_name1, from_d, to_d)
	LOOP 
		x1[i] = r.date;
		y1[i] = r.sum;
		i = i + 1;
	END LOOP;
	
	FOR r1 IN SELECT *
		FROM UDF_2(gauge_name2, from_d, to_d)
	LOOP 
		x2[j] = r1.date;
		y2[j] = r1.sum;
		j = j + 1;
	END LOOP;
	RETURN UDF_13(path, gauge_name1, gauge_name2, 
			x1, y1, x2, y2);
END
$BODY$
  LANGUAGE 'plpgsql';
  

--------------------------------------------------------------------------------------------------------------
-- funzione che dati il path del file e la data filtra il contenuto del file stesso nella tabella precipitation --
--------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_0(path text, data text)
RETURNS SETOF record AS
$BODY$
	x <- read.table(path, header = TRUE, sep = '\t',as.is = TRUE, dec = ',', na.string = 'ND', quote='\"', colClasses=c(ora='character'));
	ris <- data.frame(cod_pluvio = x$cod_pluvio, ora = x$ora, stazione = x$stazione, dpe = x$dpe, data= rep(data, length(x$cod_pluvio)));
	return (ris);
END
$BODY$ LANGUAGE 'plr';

------------------------------------------------------------------------------------------------------------------------
-- funzione che dati il path di un file .dat e la data inserisce il contenuto del file stesso nella tabella precipitation --
------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION import_precipitation(path text, data text)
RETURNS void AS
$BODY$
	INSERT INTO precipitation (gauge, date, time, accumulated) SELECT gauge, date, time, accumlated FROM UDF_0(path, data) t(gauge integer, time time, station text, accumlated double precision, date date)
	
$BODY$ LANGUAGE SQL;




----------------------------
-- Funzioni in appendice  --
----------------------------

---------------------------------------------------------------------------------------------------------
-- funzione che dati il nome di una stazione e un intervallo di mesi calcola la somma delle rainfall   --                                                                                                       
---------------------------------------------------------------------------------------------------------

  CREATE OR REPLACE FUNCTION UDF_24(gauge_name text, from_m text, to_m text)
  RETURNS SETOF rainfall AS
$BODY$
DECLARE 
	row rainfall;

	g integer;
	m1 integer;
	m2 integer;
	y integer;

	i integer;
	tmp double precision;

	ret rainfall;
BEGIN

	m1 = substring(from_m from 6 for 2);
	m2 = substring(to_m from 6 for 2);
	y = substring(to_m from 1 for 4);
	ret.sum = 0;
	
	FOR i IN m1..m2 LOOP
		tmp = 0;
		
		IF (i = 4 OR i = 6 OR i = 9 OR i = 11) THEN
			g = 30;
		ELSE IF (i = 2) THEN
			IF (y%4 = 0 AND (y%100 != 0 OR y%400 = 0)) THEN
				g = 29;
			ELSE
				g = 28;
			END IF;
		ELSE 
			g = 31;
		END IF;
		END IF;
		
		for row IN SELECT * FROM UDF_2(gauge_name, y || '-' || i || '-01', y || '-' || i || '-' || g)
		LOOP
			IF row.sum IS NOT NULL THEN 
				tmp =  row.sum;
			END IF;
		END LOOP;
		ret.sum = ret.sum + tmp;
		ret.date = y || '-' || i || '-' || g;
		return next ret;
		
	END LOOP;
	
END
$BODY$
  LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION UDF_25(gauge_name text, from_y text, to_y text)
  RETURNS SETOF rainfall AS
$BODY$
DECLARE 
	row rainfall;
	
	i integer;
	tmp double precision;

	ret rainfall;
BEGIN
	ret.sum = 0;
	
	FOR i IN from_y..to_y LOOP
		tmp = 0;
		
		for row IN SELECT * FROM UDF_24(gauge_name, i || '-01', i || '-12')
		LOOP
			IF row.sum IS NOT NULL THEN 
				tmp =  row.sum;
			END IF;
		END LOOP;
		ret.sum = ret.sum + tmp;
		ret.date = i || '-12-31';
		return next ret;
		
	END LOOP;
	
END
$BODY$
  LANGUAGE plpgsql;

--------------------------------------------------------------------------------------------------------------
--    --                                                                                                       
--------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION UDF_26(from_m text, to_m text)
  RETURNS SETOF rainfall_location AS
$BODY$
DECLARE 
	row rainfall_location;

	g integer;
	m2 integer;
	y integer;

	f text;
	t text;
BEGIN
	m2 = substring(to_m from 6 for 2);
	y = substring(to_m from 1 for 4);

	IF (m2 = 4 OR m2 = 6 OR m2 = 9 OR m2 = 11) THEN 
		g = 30;
	ELSE IF (m2 = 2) THEN
		IF (y%4 = 0 AND (y%100 != 0 OR y%400 = 0)) THEN
			g = 29;
		ELSE
			g = 28;
		END IF;
	ELSE 
		g = 31;
	END IF;
	END IF;

	f = from_m || '-01';
	t = to_m || '-' || g;
	
	FOR row IN SELECT r.id_gauge, r.name, r.location, SUM(d.accumulated)
		FROM rain_gauge AS r, precipitation AS d
		WHERE r.id_gauge = d.gauge AND 
			d.date BETWEEN CAST(f AS date) AND CAST(t AS date)		
			GROUP BY r.id_gauge		
	LOOP
		RETURN NEXT row;
	END LOOP;
END;
$BODY$
  LANGUAGE plpgsql;

--------------------------------------------------------------------------------------------------------------
--    --                                                                                                       
--------------------------------------------------------------------------------------------------------------

  CREATE OR REPLACE FUNCTION UDF_27(from_y text, to_y text)
  RETURNS SETOF rainfall_location AS
$BODY$
DECLARE 
	row rainfall_location;

	f text;
	t text;
BEGIN
	f = from_y || '-01-01';
	t = to_y || '-12-31';
	
	FOR row IN SELECT r.id_gauge, r.name, r.location, SUM(d.accumulated)
		FROM rain_gauge AS r, precipitation AS d
		WHERE r.id_gauge = d.gauge AND 
			d.date BETWEEN CAST(f AS date) AND CAST(t AS date)		
			GROUP BY r.id_gauge		
	LOOP
		RETURN NEXT row;
	END LOOP;
END;
$BODY$
  LANGUAGE plpgsql;
  
  
  CREATE OR REPLACE FUNCTION UDF_28(path text, gauge_name text, x1 date[], y double precision[])
  RETURNS boolean AS
$BODY$

	x2 <- as.Date(x1, format = '%Y-%m-%d');
	x <- as.double(x2);
	l <- length(x);
	pdf(path);
	plot(x,y, xlab = 'Date [yyyy-mm-dd]', ylab = 'Rainfall [mm]', main = paste('Rainfall at ', gauge_name, ' rain gauge'), xaxt = 'n');
	axis(1, at = c(x[1], x[(l)/4], x[l/2], x[(3*l)/4], x[l]), labels = c(x1[1], x1[(l)/4], x1[l/2], x1[(3*l)/4], x1[l]));
	lines(x, y, col = 'blue', lwd = 2);
	legend("topleft", c('Rainfall Value','Straight Line'), lty=c(-1,1), pch=c(1,-1), col=c('black','blue'), lwd=c(-1,2), merge =TRUE);
	dev.off();
	return (TRUE);

$BODY$
  LANGUAGE plr;

-------------------------------------------------------------------------------------------------------------------------------
-- funzione che esegue il plot completo dei dati presi dalla funzione UDF_24 in un file pdf specificato in path --                                                                                                       
-------------------------------------------------------------------------------------------------------------------------------

  CREATE OR REPLACE FUNCTION plot_withinMonths(path text, gauge_name text, from_m text, to_m text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfall;
	x date[];
	y double precision[];
	i integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_24(gauge_name, from_m, to_m)
	LOOP 
		x[i] = r.date;
		y[i] = r.sum;
		i = i + 1;
	END LOOP;
	RETURN UDF_28(path, gauge_name, x, y);
END
$BODY$
  LANGUAGE 'plpgsql';

--------------------------------------------------------------------------------------------------------------
-- funzione che esegue il plot completo dei dati specificati da x1 e y in un file pdf specificato in path   --                                                                                                       
--------------------------------------------------------------------------------------------------------------

  CREATE OR REPLACE FUNCTION UDF_29(path text, gauge_name text, x1 date[], y double precision[])
  RETURNS boolean AS
$BODY$

	x2 <- as.POSIXlt(x1)$year+1900;
	x <- as.double(x2);
	l <- length(x);
	pdf(path);
	plot(x,y, xlab = 'Year [yyyy]', ylab = 'Rainfall [mm]', main = paste('Rainfall at ', gauge_name, ' rain gauge'), xaxt = 'n');
	axis(1, at = c(x[1], x[(l)/4], x[l/2], x[(3*l)/4], x[l]), labels = c(x2[1], x2[(l)/4], x2[l/2], x2[(3*l)/4], x2[l]));
	lines(x, y, col = 'blue', lwd = 2);
	legend("topleft", c('Rainfall Value','Zigzag Curve'), lty=c(-1,1), pch=c(1,-1), col=c('black','blue'), lwd=c(-1,2), merge =TRUE);
	dev.off();
	return (TRUE);

$BODY$
  LANGUAGE 'plr';

---------------------------------------------------------------------------------------------------------
-- funzione che dati il nome di una stazione e un intervallo di anni calcola la somma delle rainfall   --                                                                                                       
---------------------------------------------------------------------------------------------------------

  CREATE OR REPLACE FUNCTION plot_withinYears(path text, gauge_name text, from_y text, to_y text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfall;
	x date[];
	y double precision[];
	i integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_25(gauge_name, from_y, to_y)
	LOOP 
		x[i] = r.date;
		y[i] = r.sum;
		i = i + 1;
	END LOOP;
	RETURN UDF_29(path, gauge_name, x, y);
END
$BODY$
  LANGUAGE 'plpgsql';
  
  
 -----------------------------------

---                    UDF di supporto
----------------------------------------- 
  
  CREATE OR REPLACE FUNCTION UDF_30(acc double precision[], path text, from_d text, to_d text)
  RETURNS boolean AS
$BODY$
pdf(path)
barplot(acc, main= paste("Rainfall at all rain gauges ", "\n from ", from_d, " to ", to_d), xlab = 'Rain gauges', ylab = 'Rainfall [mm]')
dev.off()
return(TRUE);
$BODY$
  LANGUAGE 'plr';
  
  CREATE OR REPLACE FUNCTION UDF_31(gauge_name text, from_y text, to_y text)
  RETURNS SETOF rainfallPlus AS
$BODY$
DECLARE
	f text;
	t text;
	row precipitation%rowtype;
	result rainfallPlus;
BEGIN
	f = from_y || '-01-01';
	t = to_y || '-12-31';

	result.sum = 0;
	FOR row IN SELECT *
		FROM precipitation AS d, rain_gauge AS r 
		WHERE r.id_gauge = d.gauge AND  
		      r.name = gauge_name AND 
		      d.date BETWEEN CAST(f as date) AND CAST(t as date)
		ORDER BY d.date
	LOOP 
		result.date = row.date;
		IF row.accumulated IS NOT NULL THEN 
			result.rain = row.accumulated;
			result.sum = result.sum + row.accumulated;
		ELSE
			result.rain = 0;
			result.sum = result.sum;
		END IF;
		RETURN NEXT result;
	END LOOP;
	RETURN;
END
$BODY$
  LANGUAGE 'plpgsql';
  
  CREATE OR REPLACE FUNCTION UDF_32(gauge_name text, from_d text, to_d text)
  RETURNS SETOF rainfallPlus AS
$BODY$
DECLARE
	row precipitation%rowtype;
	result rainfallPlus;
BEGIN
	result.sum = 0;
	FOR row IN SELECT *
		FROM precipitation AS d, rain_gauge AS r 
		WHERE r.id_gauge = d.gauge AND  
		      r.name = gauge_name AND 
		      d.date BETWEEN CAST(from_d as date) AND CAST(to_d as date)
		ORDER BY d.date
	LOOP 
		result.date = row.date;
		IF row.accumulated IS NOT NULL THEN 
			result.rain = row.accumulated;
			result.sum = result.sum + row.accumulated;
		ELSE
			result.rain = 0;
			result.sum = result.sum;
		END IF;
		RETURN NEXT result;
	END LOOP;
	RETURN;
END
$BODY$
  LANGUAGE 'plpgsql';
  
  CREATE OR REPLACE FUNCTION UDF_33(path text, gauge_name text, x1 date[], y double precision[], s double precision[])
  RETURNS boolean AS
$BODY$

	x2 <- as.Date(x1, format = '%Y-%m-%d');
	x <- as.double(x2);
	l <- length(x);
	pdf(path);
	barplot(y, xlab = 'Date (LT) [yyyy-mm-dd]', ylab = 'Rainfall [mm]', main = paste('Rainfall at ', gauge_name, ' rain gauge'), xaxt = 'n');
	par (new = T);
	plot(x, s, type = 'l', yaxt = 'n', xaxt = 'n', xlab = '', ylab = '', col ='blue', lwd = 2);
	axis(1, at = c(x[1], x[l/4], x[l/2], x[(3*l)/4], x[l]), labels = c(x1[1], x1[l/4], x1[l/2], x1[(3*l)/4], x1[l]));
	axis(4);
	legend("topleft", 'Zigzag Curve', lty= 1, pch= -1, col= 'blue', lwd= 2);
	dev.off();
	return (TRUE);

$BODY$
  LANGUAGE 'plr';
  
  CREATE OR REPLACE FUNCTION UDF_34(gauge_name text, from_m text, to_m text)
  RETURNS SETOF rainfallPlus AS
$BODY$
DECLARE
	g integer;
	m2 integer;
	y integer;

	f text;
	t text;
	row precipitation%rowtype;
	result rainfallPlus;
BEGIN
	m2 = substring(to_m from 6 for 2);
	y = substring(to_m from 1 for 4);

	IF (m2 = 4 OR m2 = 6 OR m2 = 9 OR m2 = 11) THEN 
		g = 30;
	ELSE IF (m2 = 2) THEN
		IF (y%4 = 0 AND (y%100 != 0 OR y%400 = 0)) THEN
			g = 29;
		ELSE
			g = 28;
		END IF;
	ELSE 
		g = 31;
	END IF;
	END IF;

	f = from_m || '-01';
	t = to_m || '-' || g;

	result.sum = 0;
	FOR row IN SELECT *
		FROM precipitation AS d, rain_gauge AS r 
		WHERE r.id_gauge = d.gauge AND  
		      r.name = gauge_name AND 
		      d.date BETWEEN CAST(f as date) AND CAST(t as date)
		ORDER BY d.date
	LOOP 
		result.date = row.date;
		IF row.accumulated IS NOT NULL THEN 
			result.rain = row.accumulated;
			result.sum = result.sum + row.accumulated;
		ELSE
			result.rain = 0;
			result.sum = result.sum;
		END IF;
		RETURN NEXT result;
	END LOOP;
	RETURN;
END
$BODY$
  LANGUAGE 'plpgsql';
  
   CREATE OR REPLACE FUNCTION rainfallPlot_withinDays(path text, gauge_name text, from_d text, to_d text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfallPlus;
	x date[];
	y double precision[];
	s double precision[];
	i integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_32(gauge_name, from_d, to_d)
	LOOP 
		x[i] = r.date;
		y[i] = r.rain;
		s[i] = r.sum;
		i = i + 1;
	END LOOP;
	RETURN UDF_33(path, gauge_name, x, y, s);
END
$BODY$
  LANGUAGE 'plpgsql';
  
  
    CREATE OR REPLACE FUNCTION barPlot_withinDays(from_d text, to_d text, path text)
  RETURNS boolean AS
$BODY$
DECLARE
	r record;
	acc double precision[];
	i integer = 1;
BEGIN

	FOR r IN SELECT SUM(accumulated) AS acc FROM precipitation AS d WHERE
			d.date > CAST (from_d AS date) 
			AND d.date < CAST (to_d AS date) 
			GROUP BY d.gauge
	LOOP
		acc[i] = r.acc;
		i = i + 1;
	END LOOP;
	RETURN UDF_30(acc, path, from_d, to_d);
END;
$BODY$
LANGUAGE 'plpgsql';
  
  
  ----------------------------------------------------------------
  --             Month e Years
  ----------------------------------------------------
  
  
  CREATE OR REPLACE FUNCTION barPlot_withinMonths(from_m text, to_m text, path text)
  RETURNS boolean AS
$BODY$
DECLARE
	g integer;
	m2 integer;
	y integer;

	f text;
	t text;

	r record;
	acc double precision[];
	i integer = 1;
BEGIN
	
	m2 = substring(to_m from 6 for 2);
	y = substring(to_m from 1 for 4);

	IF (m2 = 4 OR m2 = 6 OR m2 = 9 OR m2 = 11) THEN 
		g = 30;
	ELSE IF (m2 = 2) THEN
		IF (y%4 = 0 AND (y%100 != 0 OR y%400 = 0)) THEN
			g = 29;
		ELSE
			g = 28;
		END IF;
	ELSE 
		g = 31;
	END IF;
	END IF;

	f = from_m || '-01';
	t = to_m || '-' || g;
	
	FOR r IN SELECT SUM(accumulated) AS acc FROM precipitation AS d 
			WHERE d.date > CAST (f AS date) 
			AND d.date < CAST (t AS date) 
			GROUP BY d.gauge
	LOOP
		acc[i] = r.acc;
		i = i + 1;
	END LOOP;
	RETURN UDF_30(acc, path, f, t);
END;
$BODY$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION barPlot_withinYears(from_y text, to_y text, path text)
  RETURNS boolean AS
$BODY$
DECLARE

	
	f text;
	t text;
	r record;
	acc double precision[];
	i integer = 1;
BEGIN
	f = from_y || '-01-01';
	t = to_y || '-12-31';
	
	FOR r IN SELECT SUM(accumulated) AS acc FROM precipitation AS d 
			WHERE d.date > CAST (f AS date) 
			AND d.date < CAST (t AS date) 
			GROUP BY d.gauge
	LOOP
		acc[i] = r.acc;
		i = i + 1;
	END LOOP;
	RETURN UDF_30(acc, path, f, t);
END;
$BODY$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION comparisonOfPlot_withinMonths(path text, gauge_name text, 
		from_m text, to_m text, from_m2 text, to_m2 text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfall;
	r1 rainfall;
	x1 date[];
	x2 date[];
	y1 double precision[];
	y2 double precision[];
	i integer = 1;
	j integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_24(gauge_name, from_m, to_m)
	LOOP 
		x1[i] = r.date;
		y1[i] = r.sum;
		i = i + 1;
	END LOOP;
	
	FOR r1 IN SELECT *
		FROM UDF_24(gauge_name, from_m2, to_m2)
	LOOP 
		x2[j] = r1.date;
		y2[j] = r1.sum;
		j = j + 1;
	END LOOP;
	RETURN UDF_11(path, gauge_name, x1, y1, x2, y2);
END
$BODY$
  LANGUAGE 'plpgsql';
  
  CREATE OR REPLACE FUNCTION comparisonOfPlot_withinMonths_betweenTwoRainGauges(path text, gauge_name1 text, 
		gauge_name2 text, from_m text, to_m text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfall;
	r1 rainfall;
	x1 date[];
	x2 date[];
	y1 double precision[];
	y2 double precision[];
	i integer = 1;
	j integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_24(gauge_name1, from_m, to_m)
	LOOP 
		x1[i] = r.date;
		y1[i] = r.sum;
		i = i + 1;
	END LOOP;
	
	FOR r1 IN SELECT *
		FROM UDF_24(gauge_name2, from_m, to_m)
	LOOP 
		x2[j] = r1.date;
		y2[j] = r1.sum;
		j = j + 1;
	END LOOP;
	RETURN UDF_13(path, gauge_name1, gauge_name2, 
			x1, y1, x2, y2);
END
$BODY$
  LANGUAGE 'plpgsql';
  
  CREATE OR REPLACE FUNCTION comparisonOfPlot_withinYears(path text, gauge_name text, 
		from_y text, to_y text, from_y2 text, to_y2 text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfall;
	r1 rainfall;
	x1 date[];
	x2 date[];
	y1 double precision[];
	y2 double precision[];
	i integer = 1;
	j integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_25(gauge_name, from_y, to_y)
	LOOP 
		x1[i] = r.date;
		y1[i] = r.sum;
		i = i + 1;
	END LOOP;
	
	FOR r1 IN SELECT *
		FROM UDF_25(gauge_name, from_y2, to_y2)
	LOOP 
		x2[j] = r1.date;
		y2[j] = r1.sum;
		j = j + 1;
	END LOOP;
	RETURN UDF_11(path, gauge_name, x1, y1, x2, y2);
END
$BODY$
  LANGUAGE 'plpgsql';
  
  CREATE OR REPLACE FUNCTION comparisonOfPlot_withinYears_betweenTwoRainGauges(path text, gauge_name1 text, 
		gauge_name2 text, from_y text, to_y text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfall;
	r1 rainfall;
	x1 date[];
	x2 date[];
	y1 double precision[];
	y2 double precision[];
	i integer = 1;
	j integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_25(gauge_name1, from_y, to_y)
	LOOP 
		x1[i] = r.date;
		y1[i] = r.sum;
		i = i + 1;
	END LOOP;
	
	FOR r1 IN SELECT *
		FROM UDF_25(gauge_name2, from_y, to_y)
	LOOP 
		x2[j] = r1.date;
		y2[j] = r1.sum;
		j = j + 1;
	END LOOP;
	RETURN UDF_13(path, gauge_name1, gauge_name2, 
			x1, y1, x2, y2);
END
$BODY$
  LANGUAGE 'plpgsql';
  
  CREATE OR REPLACE FUNCTION rainfallPlot_withinMonths(path text, gauge_name text, from_m text, to_m text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfallPlus;
	x date[];
	y double precision[];
	s double precision[];
	i integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_34(gauge_name, from_m, to_m)
	LOOP 
		x[i] = r.date;
		y[i] = r.rain;
		s[i] = r.sum;
		i = i + 1;
	END LOOP;
	RETURN UDF_33(path, gauge_name, x, y, s);
END
$BODY$
  LANGUAGE 'plpgsql';
  
  CREATE OR REPLACE FUNCTION rainfallPlot_withinYears(path text, gauge_name text, from_y text, to_y text)
  RETURNS boolean AS
$BODY$
DECLARE 
	r rainfallPlus;
	x date[];
	y double precision[];
	s double precision[];
	i integer = 1;
BEGIN 
	FOR r IN SELECT *
		FROM UDF_31(gauge_name, from_y, to_y)
	LOOP 
		x[i] = r.date;
		y[i] = r.rain;
		s[i] = r.sum;
		i = i + 1;
	END LOOP;
	RETURN UDF_33(path, gauge_name, x, y, s);
END
$BODY$
  LANGUAGE 'plpgsql';
  


  
  
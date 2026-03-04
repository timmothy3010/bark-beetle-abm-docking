model Borkenkaefer_FIXED_FINAL

global {
    // --- FILES & PARAMETERS ---
    file shape_file_trees <- file("../includes/FP_treeBOXES.shp");
    file temp_csv_file <- csv_file("../includes/temperatures_pointdecimal.CSV", ";", true);
    matrix data_temp_matrix <- matrix(temp_csv_file);

    // Parameters
    float tempvalue <- 4.0 parameter: "Temp SD (tempvalue)";
    int Beetleonpatch <- 5 parameter: "Max Käfer pro Patch"; 
    int maxbeetles <- 200000 parameter: "Max Beetles Threshold";
    int Managementnumber <- 3 parameter: "Management Number"; 
    bool management <- false parameter: "Management Aktiv?";
    bool klimakrise <- false parameter: "Klimakrise?";
    bool Extremevent <- false parameter: "Extremevent?";
    float todeschance <- 5.0 parameter: "Todeschance";
    bool Windwurf <- false parameter: "Windwurf?";
    bool exact_port_mode <- true parameter: "Exact NetLogo Port";
    bool debug_mode <- false parameter: "Debug Mode (verbose output)";
    bool is_batch <- false;

    // Globals
    int week <- 0;
    int month <- 0; 
    int year <- 2000;
    float temp <- 0.0;
    int maxbeetle <- 0;
    int counteggs <- 0;
    float maxbefall <- 0.0;
    bool maxbeetlechecker <- false;
    int tick_counter <- 0;  // Starts at 0, will be incremented to 1 first thing
    
    // Debug counters
    int beetles_moved_this_cycle <- 0;
    int winter_deaths_this_cycle <- 0;
    
    geometry full_bounds <- envelope(shape_file_trees);
    geometry crop_box <- square(11500.0) at_location full_bounds.location;
    geometry shape <- exact_port_mode ? crop_box : full_bounds;

    init {
        write "========================================";
        write "=== BEETLE MODEL INITIALIZATION ===";
        write "========================================";
        
        // CSV Debug
        write "CSV loaded: " + data_temp_matrix.rows + " rows x " + data_temp_matrix.columns + " columns";
        
        // Random background
        ask forest_cell {
            int randomzahl <- rnd(2);
            if (randomzahl = 0) { Baumart <- "4"; }
            else if (randomzahl = 1) { Baumart <- "1"; }
            else { Baumart <- "3"; }
            do update_cell_color;
        }
        
        // Background Festmeter for non-shapefile cells
        ask forest_cell {
            if (Festmeter = 0) {
                Festmeter <- 300.0 - rnd(300) + rnd(300);
            }
        }

        // Load shapefile
        create stand_data from: shape_file_trees with: [
            baumart_str::string(read("WORD")), 
            vol::float(read("VOL_AO")),
            count_val::int(read("COUNT")),
            id_val::int(read("ID"))
        ];
        
        write "Shapefile loaded: " + length(stand_data) + " features";

        // Apply shapefile data
        ask stand_data {
            if (self overlaps world.shape) {
                forest_cell cell_under_me <- forest_cell(location);
                if (cell_under_me != nil) {
                    ask cell_under_me {
                        Baumart <- myself.baumart_str;
                        Fastmeter <- myself.vol;
                        Baumanzahl <- myself.count_val;
                        Id <- myself.id_val;
                        if (Fastmeter > 0) { Festmeter <- Fastmeter; }
                        do update_cell_color;
                    }
                }
            }
        }
        ask stand_data { do die; }
        
        // Management
        if (management) {
            int converted <- 0;
            ask forest_cell where (each.Baumart = "1") {
                int spruce_neighbors <- neighbors count (each.Baumart = "1");
                if (spruce_neighbors < Managementnumber) {
                    Baumart <- "3";
                    do update_cell_color;
                    converted <- converted + 1;
                }
            }
            write "Management: " + converted + " spruce cells converted";
        }
        
        // CRITICAL: Initial Totholz
        ask forest_cell where (each.Festmeter > 0) {
            Totholz <- 17.0;
        }

        // Beetle spawning
        list<forest_cell> spruce_cells <- forest_cell where (each.Baumart = "1");
        
        if (length(spruce_cells) < 7) {
            spruce_cells <- 7 among forest_cell;
        } else {
            spruce_cells <- 7 among spruce_cells;
        }
        
        ask spruce_cells {
            create beetle number: 3 {
                location <- myself.location;
                energy <- rnd(21) + 5;
                lifecount <- 0;
                waittime <- 0;
            }
            
            list<forest_cell> spruce_neighbors <- neighbors where (each.Baumart = "1");
            ask spruce_neighbors {
                create beetle number: 3 {
                    location <- myself.location;
                    energy <- rnd(21) + 5;
                    lifecount <- 0;
                    waittime <- 0;
                }
            }
        }
        
        write "Initial beetles: " + length(beetle);
        
        // Initial temperature
        do get_temperature_from_csv;
        write "Initial temperature: " + temp;
        write "========================================";
    }

    // CRITICAL FIX: NetLogo order is tick → progresstime → check → move
    reflex go {
        if (year >= 2020) { do pause; }
        
        // Reset cycle counters
        beetles_moved_this_cycle <- 0;
        winter_deaths_this_cycle <- 0;
        
        // 1. INCREMENT TICK FIRST (like NetLogo's 'tick' at start of 'go')
        tick_counter <- tick_counter + 1;
        
        // 2. THEN process time logic
        do progresstime;
        
        // 3. Count beetles per cell
        do check;
        
        // 4. Movement phase (April-August, temp >= 16)
        if (month >= 3 and month <= 7) {
            if (temp >= 16) {
                ask beetle { do move; }
            }
        }

        // 5. Count eggs
        counteggs <- forest_cell count (each.Eier > 0 or each.Eier2 > 0 or each.Eier3 > 0 or each.Eier4 > 0);
        
        // 6. Winter deaths (Feb, Mar, Sep, Oct)
        if (month = 1 or month = 2 or month = 8 or month = 9) {
            ask beetle {
                forest_cell my_cell <- forest_cell(location);
                if (my_cell.Baumart != "1") { 
                    winter_deaths_this_cycle <- winter_deaths_this_cycle + 1;
                    do die; 
                }
            }
        }
        
        // Debug output
        if (debug_mode and (tick_counter = 1 or tick_counter = 35)) {
            write "Tick=" + tick_counter + " Year=" + year + " Month=" + month + " Week=" + week + " Beetles=" + length(beetle) + " Temp=" + temp + " Moved=" + beetles_moved_this_cycle;
        }
    }
    

// --- DATEN SCHREIBEN (Nur im Batch Modus aktiv) ---
    reflex save_batch_data when: is_batch {
        string my_output_file <- "../includes/gama_results_" + int(self) + ".csv";
        list<string> headers <- ["run_id", "step", "beetles", "wood_damage"];
        bool is_new_file <- (cycle = 0);
        
        // FIX: Wir berechnen den Schaden LIVE, genau wie NetLogos "sum [Totmeter] of patches"
        float current_damage <- forest_cell sum_of (each.Totmeter);
        
        // Debugging: Falls immer noch 0, schauen wir, ob überhaupt Festmeter da sind
        if (cycle = 1 and current_damage = 0 and length(beetle) > 50) {
             float total_biomass <- forest_cell sum_of (each.Festmeter);
             write "DEBUG RUN " + int(self) + ": Totale Biomasse im Wald: " + total_biomass;
             if (total_biomass = 0) { write "ALARM: Keine Festmeter geladen!"; }
        }

        save [int(self), cycle, length(beetle), current_damage] 
             to: my_output_file 
             format: "csv" 
             rewrite: is_new_file 
             header: is_new_file ? headers : []; 
    }

    action progresstime {
        // Temperature updates at ticks 7, 14, 21, 28 (AFTER increment, so these values are correct)
        if (tick_counter = 7 or tick_counter = 14 or tick_counter = 21 or tick_counter = 28) {
            do get_temperature_from_csv;
            if (klimakrise) { temp <- temp + 4.5; }
        }

        // Week transition at tick 35
        if (tick_counter = 35) {
            week <- week + 1;
            tick_counter <- 0;  // Reset for next week
            
            // Egg development
            ask forest_cell {
                do egg;
                do egg2;
                do egg3;
                do egg4;
            }
            
            do get_temperature_from_csv;
            if (klimakrise) { temp <- temp + 4.5; }

            ask beetle where (each.waittime > 0) {
                waittime <- waittime - 1;
            }
        }
        
        if (length(beetle) > maxbeetle) { 
            maxbeetle <- length(beetle);
        }

        // Month transition
        if (week = 4) {
            month <- month + 1;
            week <- 0;
            do sterben;
        }

        // Year transition
        if (month = 12) {
            if (debug_mode) {
                write "=== YEAR " + year + " COMPLETE ===";
                write "Final beetles: " + length(beetle);
            }
            
            year <- year + 1;
            month <- 0;
            
            do settotholz;
            if (Windwurf) { do windfall; }
            
            // Oldest generation dies
            ask beetle where (each.lifecount = 2) { do die; }
            
            // Cleanup
            
            
            ask forest_cell where (each.Befall) {
                Befall <- false;
                Totmeter <- 0.0;
            }
            ask forest_cell where (each.pheromon) {
                pheromon <- false;
            }
            
            // Winter mortality (45%)
            int before_winter <- length(beetle);
            ask beetle {
                if (rnd(100) < 45) { do die; }
            }
            
            if (debug_mode) {
                write "Year-end mortality: " + (before_winter - length(beetle)) + " beetles";
                write "Starting Year " + year + " with " + length(beetle) + " beetles";
            }
            
            if (length(beetle) > maxbeetles) {
                maxbeetlechecker <- true;
            } else {
                maxbeetlechecker <- false;
            }
        }
        
        maxbefall <- forest_cell where (each.Baumart="1" and each.Totmeter > 0) sum_of (each.Totmeter);
    }
    
    action check {
        ask forest_cell {
            Anzahl <- length(beetle inside self);
        }
    }

    action get_temperature_from_csv {
        float mean_temp <- 0.0;
        bool found <- false;
        
        loop i from: 0 to: data_temp_matrix.rows - 1 {
            // CSV Month is 1-12, model month is 0-11
            if (int(data_temp_matrix[0,i]) = year and int(data_temp_matrix[1,i]) = (month + 1)) {
                mean_temp <- float(data_temp_matrix[2,i]);
                found <- true;
                break;
            }
        }
        
        if (!found) {
            write "WARNING: No temperature data for Year=" + year + " Month=" + (month + 1);
            mean_temp <- 10.0;
        }
        
        temp <- gauss(mean_temp, tempvalue);
    }
    
    action settotholz {
        float wert <- 17.0;
        
        if (year = 2000) { wert <- 17.0; }
        else if (year = 2001) { wert <- 18.0; }
        else if (year = 2002) { wert <- 18.5; }
        else if (year = 2003) { wert <- 19.0; }
        else if (year = 2004) { wert <- 20.0; }
        else if (year = 2005) { wert <- 21.0; }
        else if (year = 2006) { wert <- 21.0; }
        else if (year = 2007) { wert <- 22.5; }
        else if (year = 2008) { wert <- 23.5; }
        else if (year = 2009) { wert <- 25.5; }
        else if (year = 2010) { wert <- 30.0; }
        else if (year = 2011) { wert <- 32.0; }
        else if (year = 2012) { wert <- 32.0; }
        else if (year = 2013) { wert <- 32.0; }
        else if (year = 2014) { wert <- 32.0; }
        else if (year = 2015) { wert <- 32.0; }
        else if (year = 2016) { wert <- 32.0; }
        else if (year = 2017) { wert <- 32.0; }
        else if (year = 2018) { wert <- 34.0; }
        else if (year = 2019) { wert <- 34.0; }
        else if (year = 2020) { wert <- 34.0; }
        else if (year = 2021) { wert <- 34.0; }
        
        ask forest_cell where (each.Festmeter > 0) {
            Totholz <- wert;
        }
    }
    
    action windfall {
        if (year = 2007 or year = 2008) {
            ask forest_cell where (each.Festmeter > 0) { 
                Totholz <- 35.0; 
            }
        }
        
        if (Extremevent and year = 2005) {
            ask forest_cell where (each.grid_x > 42 and each.grid_x < 72) {
                Totholz <- 35.0;
            }
        }
    }
    
    action sterben {
        float limit0 <- todeschance;
        float limit1 <- todeschance + 10.0;
        
        if (maxbeetlechecker) { 
            limit0 <- todeschance - 3.0;
            limit1 <- todeschance;
        }
        
        ask beetle where (each.lifecount = 0) {
            if (rnd(100.0) < limit0) { do die; }
        }
        ask beetle where (each.lifecount = 1) {
            if (rnd(100.0) < limit1) { do die; }
        }
    }
}

grid forest_cell width: 115 height: 115 neighbors: 8 { 
    string Baumart <- "0";
    int Baumanzahl <- 0;
    int Id <- 0;
    float Fastmeter <- 0.0;
    float Festmeter <- 0.0;
    
    float Eier <- 0.0;
    float Eier2 <- 0.0;
    float Eier3 <- 0.0;
    float Eier4 <- 0.0;
    
    int Anzahl <- 0;
    bool pheromon <- false;
    bool Befall <- false;
    float Totholz <- 0.0;
    float Totmeter <- 0.0;
    
    int Befallszahl <- 0;
    int Befallszahl2 <- 0;
    int Befallszahl3 <- 0;
    int Befallszahl4 <- 0;
    
    aspect default {
        draw shape color: color border: #transparent; 
    }
    
    action update_cell_color {
        if (Baumart = "3") { color <- rgb(144, 238, 144); }
        else if (Baumart = "1") { color <- rgb(50, 205, 50); }
        else if (Baumart = "4") { color <- rgb(150, 75, 0); }
        else { color <- #gray; }
    }

    action egg {
        if (Eier > 0) {
            float reduction <- 0.65;
            if (temp >= 30) { reduction <- 2.0; }
            else if (temp >= 25) { reduction <- 1.7 + rnd(0.1); }
            else if (temp >= 20) { reduction <- 1.2 + rnd(0.3); }
            else if (temp >= 15) { reduction <- 0.8 + rnd(0.3); }
            
            Eier <- Eier - reduction;
            
            if (Eier <= 0) {
                Eier <- 0.0;
                int total_befall <- Befallszahl + Befallszahl2 + Befallszahl3 + Befallszahl4;
                
                if (total_befall <= 2) {
                    if (rnd(100) < 90) {
                        create beetle number: (3 + rnd(4)) * Befallszahl {
                            location <- myself.location;
                            energy <- rnd(11) + 5;
                            lifecount <- 0;
                            waittime <- 0;
                        }
                    }
                }
                else if (total_befall > 2 and total_befall <= 4) {
                    if (rnd(100) < 90) {
                        create beetle number: (2 + rnd(2)) * Befallszahl {
                            location <- myself.location;
                            energy <- rnd(11) + 5;
                            lifecount <- 0;
                            waittime <- 0;
                        }
                    }
                }
                else if (total_befall > 4) {
                    if (rnd(100) < 90) {
                        create beetle number: (1 + rnd(2)) * Befallszahl {
                            location <- myself.location;
                            energy <- rnd(11) + 5;
                            lifecount <- 0;
                            waittime <- 0;
                        }
                    }
                }
                Befallszahl <- 0;
            }
        }
    }
    
    action egg2 {
        if (Eier2 > 0) {
            float reduction <- 0.65;
            if (temp >= 30) { reduction <- 2.0; }
            else if (temp >= 25) { reduction <- 1.7 + rnd(0.1); }
            else if (temp >= 20) { reduction <- 1.2 + rnd(0.3); }
            else if (temp >= 15) { reduction <- 0.8 + rnd(0.3); }
            
            Eier2 <- Eier2 - reduction;
            
            if (Eier2 <= 0) {
                Eier2 <- 0.0;
                int total_befall <- Befallszahl + Befallszahl2 + Befallszahl3 + Befallszahl4;
                
                if (total_befall <= 2) {
                    if (rnd(100) < 80) {
                        create beetle number: (3 + rnd(3)) * Befallszahl2 {
                            location <- myself.location;
                            energy <- rnd(11) + 5;
                            lifecount <- 0;
                            waittime <- 0;
                        }
                    }
                }
                else if (total_befall > 2 and total_befall <= 4) {
                    if (rnd(100) < 80) {
                        create beetle number: (2 + rnd(2)) * Befallszahl2 {
                            location <- myself.location;
                            energy <- rnd(11) + 5;
                            lifecount <- 0;
                            waittime <- 0;
                        }
                    }
                }
                else if (total_befall > 4) {
                    if (rnd(100) < 80) {
                        create beetle number: (1 + rnd(2)) * Befallszahl2 {
                            location <- myself.location;
                            energy <- rnd(11) + 5;
                            lifecount <- 0;
                            waittime <- 0;
                        }
                    }
                }
                Befallszahl2 <- 0;
            }
        }
    }
    
    action egg3 {
        if (Eier3 > 0) {
            float reduction <- 0.65;
            if (temp >= 30) { reduction <- 2.0; }
            else if (temp >= 25) { reduction <- 1.7 + rnd(0.1); }
            else if (temp >= 20) { reduction <- 1.2 + rnd(0.3); }
            else if (temp >= 15) { reduction <- 0.8 + rnd(0.3); }
            
            Eier3 <- Eier3 - reduction;
            
            if (Eier3 <= 0) {
                Eier3 <- 0.0;
                int total_befall <- Befallszahl + Befallszahl2 + Befallszahl3 + Befallszahl4;
                
                if (total_befall <= 2) {
                    if (rnd(100) < 75) {
                        if (Totholz > 30) {
                            create beetle number: (3 + rnd(3)) * Befallszahl3 {
                                location <- myself.location;
                                energy <- rnd(11) + 5;
                                lifecount <- 0;
                                waittime <- 0;
                            }
                        } else {
                            create beetle number: 3 * Befallszahl3 {
                                location <- myself.location;
                                energy <- rnd(11) + 5;
                                lifecount <- 0;
                                waittime <- 0;
                            }
                        }
                    }
                }
                else if (total_befall > 2 and total_befall <= 4) {
                    if (rnd(100) < 75) {
                        if (Totholz > 30) {
                            create beetle number: (2 + rnd(2)) * Befallszahl3 {
                                location <- myself.location;
                                energy <- rnd(11) + 5;
                                lifecount <- 0;
                                waittime <- 0;
                            }
                        } else {
                            create beetle number: 2 * Befallszahl3 {
                                location <- myself.location;
                                energy <- rnd(11) + 5;
                                lifecount <- 0;
                                waittime <- 0;
                            }
                        }
                    }
                }
                else if (total_befall > 4) {
                    if (rnd(100) < 75) {
                        if (Totholz > 30) {
                            create beetle number: (1 + rnd(2)) * Befallszahl3 {
                                location <- myself.location;
                                energy <- rnd(11) + 5;
                                lifecount <- 0;
                                waittime <- 0;
                            }
                        } else {
                            create beetle number: 1 * Befallszahl3 {
                                location <- myself.location;
                                energy <- rnd(11) + 5;
                                lifecount <- 0;
                                waittime <- 0;
                            }
                        }
                    }
                }
                Befallszahl3 <- 0;
            }
        }
    }
    
    action egg4 {
        if (Eier4 > 0) {
            float reduction <- 0.65;
            if (temp >= 30) { reduction <- 2.0; }
            else if (temp >= 25) { reduction <- 1.7 + rnd(0.1); }
            else if (temp >= 20) { reduction <- 1.2 + rnd(0.3); }
            else if (temp >= 15) { reduction <- 0.8 + rnd(0.3); }
            
            Eier4 <- Eier4 - reduction;
            
            if (Eier4 <= 0) {
                Eier4 <- 0.0;
                int total_befall <- Befallszahl + Befallszahl2 + Befallszahl3 + Befallszahl4;
                
                if (total_befall <= 2) {
                    if (rnd(100) < 65) {
                        if (Totholz > 30) {
                            create beetle number: (2 + rnd(3)) * Befallszahl4 {
                                location <- myself.location;
                                energy <- rnd(11) + 5;
                                lifecount <- 0;
                                waittime <- 0;
                            }
                        } else {
                            create beetle number: 2 * Befallszahl4 {
                                location <- myself.location;
                                energy <- rnd(11) + 5;
                                lifecount <- 0;
                                waittime <- 0;
                            }
                        }
                    }
                }
                else if (total_befall > 2 and total_befall <= 4) {
                    if (rnd(100) < 50) {
                        if (Totholz > 30) {
                            create beetle number: (1 + rnd(2)) * Befallszahl4 {
                                location <- myself.location;
                                energy <- rnd(11) + 5;
                                lifecount <- 0;
                                waittime <- 0;
                            }
                        } else {
                            create beetle number: 1 * Befallszahl4 {
                                location <- myself.location;
                                energy <- rnd(11) + 5;
                                lifecount <- 0;
                                waittime <- 0;
                            }
                        }
                    }
                }
                else if (total_befall > 4) {
                    if (rnd(100) < 50) {
                        if (Totholz > 30) {
                            create beetle number: (1 + rnd(1)) * Befallszahl4 {
                                location <- myself.location;
                                energy <- rnd(11) + 5;
                                lifecount <- 0;
                                waittime <- 0;
                            }
                        } else {
                            create beetle number: 1 * Befallszahl4 {
                                location <- myself.location;
                                energy <- rnd(11) + 5;
                                lifecount <- 0;
                                waittime <- 0;
                            }
                        }
                    }
                }
                Befallszahl4 <- 0;
            }
        }
    }
    
	action check_befall_threshold {
	        bool triggered <- false;
	        int total_beetles <- Befallszahl + Befallszahl2 + Befallszahl3 + Befallszahl4;
	        
	        // --- DEBUG MONITOR ---
	        // Wenn ordentlich was los ist (>100 Angriffe), sag uns Bescheid!
	        // So sehen wir, ob wir knapp scheitern (z.B. 390 vs 400) oder total daneben liegen.
	        if (total_beetles > 100) {
	            write "DEBUG CHECK: Zelle " + location + " hat " + total_beetles + " Angriffe. (Festmeter: " + Festmeter + ")";
	            if (Festmeter > 0 and Festmeter < 250) { write " -> Ziel: " + Beetleonpatch + " nötig."; }
	            else if (Festmeter >= 250) { write " -> Ziel: " + (Beetleonpatch * 1.5) + " nötig."; }
	        }
	        // ---------------------
	
	        if (Festmeter > 0 and Festmeter < 250) {
	            if (total_beetles >= Beetleonpatch) { triggered <- true; }
	        }
	        else if (Festmeter >= 250 and Festmeter < 350) {
	            if (total_beetles >= Beetleonpatch * 1.5) { triggered <- true; }
	        }
	        else if (Festmeter >= 350 and Festmeter < 450) {
	            if (total_beetles >= Beetleonpatch * 2.0) { triggered <- true; }
	        }
	        else if (Festmeter >= 450) {
	            if (total_beetles >= Beetleonpatch * 3.0) { triggered <- true; }
	        }
	        
	        if (triggered) {
	            write "!!! TREFFER !!! Zelle " + location + " ist gefallen! Totholz: " + Festmeter;
	            Befall <- true;
	            pheromon <- false;
	            Totmeter <- Totmeter + Festmeter;
	        }
	    }
}

species stand_data {
    string baumart_str;
    float vol;
    int count_val;
    int id_val;
}

species beetle {
    int energy <- 0;
    int lifecount <- 0;
    int waittime <- 0;
    
    aspect default {
        draw circle(25) color: #yellow border: #black;
    }

// --- MOVE LOGIK (1:1 NetLogo "Teleport" Logic) ---
    action move {
        // NetLogo: ask beetle with [waittime = 0]
        if (waittime > 0) { return; }

        forest_cell my_cell <- forest_cell(location);
        
        // ---------------------------------------------------------
        // BLOCK A: Viel Energie (> 5) -> Random Walk
        // ---------------------------------------------------------
        if (energy > 5) {
            // NetLogo: move-to one-of neighbors
            if (!empty(my_cell.neighbors)) {
                location <- one_of(my_cell.neighbors).location;
                energy <- energy - 1;
            } else {
                do die; // Schutz gegen Kartenrand
            }
        } 
        
        // ---------------------------------------------------------
        // BLOCK B: Suche (Energie 1 bis 5) -> "Hinlaufen"
        // ---------------------------------------------------------
        else if (energy > 0) {
            // NetLogo: patches in-radius 2
            // GAMA: neighbors (Radius 1) + neighbors_at 2 (Radius 2)
            //OLD: list<forest_cell> radius_2_cells <- (my_cell.neighbors + (my_cell neighbors_at 2));
            
            list<forest_cell> radius_2_cells <- forest_cell at_distance 200.0; //should be equal to NetLogo in-radius 2
            
            // Filter: Anzahl < Limit AND pheromon = true
            list<forest_cell> attractive <- radius_2_cells where (each.pheromon and each.Anzahl < Beetleonpatch);
            
            if (!empty(attractive)) {
                // NetLogo: face ... fd 1 
                // BEDEUTUNG: Drehe dich zum Ziel und gehe 1 Schritt (auf den nächsten Nachbarn zu)
                
                forest_cell target <- one_of(attractive); // "one-of patches..."
                
                // Wir beamen uns NICHT zum Ziel, sondern zum Nachbarn, der am nächsten zum Ziel liegt
                forest_cell step_towards <- my_cell.neighbors closest_to target;
                
                location <- step_towards.location;
                energy <- energy - 1;
            } else {
                // NetLogo: move-to one-of neighbors
                if (!empty(my_cell.neighbors)) {
                    location <- one_of(my_cell.neighbors).location;
                    energy <- energy - 1;
                }
            }
        }
        
        // ---------------------------------------------------------
        // BLOCK C: Panik (Energie 0) -> "Teleportieren"
        // ---------------------------------------------------------
        else { 
            // C1. Suche im Radius 2
            list<forest_cell> radius_2_cells <- (my_cell.neighbors + (my_cell neighbors_at 2));
            list<forest_cell> attractive <- radius_2_cells where (each.pheromon and each.Anzahl < Beetleonpatch);
            
            if (!empty(attractive)) {
                // NetLogo: move-to one-of ...
                // WICHTIG: Hier "beamen" wir uns sofort hin, auch wenn es 200m weg ist!
                location <- one_of(attractive).location;
                // Keine Energiekosten (ist eh 0)
            } 
            else {
                // C2. Prüfen ob aktueller Patch schlecht ist
                // NetLogo: if [Anzahl] >= Limit or [Befall] or [pcolor] != 53
                if (my_cell.Anzahl >= Beetleonpatch or my_cell.Befall or my_cell.Baumart != "1") {
                    
                    // Prio A: Nachbar mit Pheromon
                    list<forest_cell> n_phero <- my_cell.neighbors where (each.pheromon);
                    
                    if (!empty(n_phero)) {
                        location <- one_of(n_phero).location;
                    } 
                    else {
                        // Prio B: Nachbar Fichte (53) ohne Befall
                        list<forest_cell> n_fichte <- my_cell.neighbors where (each.Baumart = "1" and !each.Befall);
                        
                        if (!empty(n_fichte)) {
                            location <- one_of(n_fichte).location;
                        } 
                        else {
                            // Prio C: Irgendein Nachbar (Verzweiflungstat)
                            if (!empty(my_cell.neighbors)) {
                                location <- one_of(my_cell.neighbors).location;
                                
                                // NetLogo: if [pcolor] of patch-here != 53 [ die ]
                                if (forest_cell(location).Baumart != "1") {
                                    do die;
                                    return; // Wichtig: Code hier abbrechen, Käfer ist tot
                                }
                            } else {
                                do die; // Sackgasse am Kartenrand
                            }
                        }
                    }
                }
                // Wenn aktueller Patch OK ist, bleiben wir einfach sitzen (implizit in NetLogo)
            }
        }
        
        // --- COLONIZATION CHECK (Muss nach dem Move passieren) ---
        // Da sich location geändert hat, update my_cell
        my_cell <- forest_cell(location); 
        
        if (dead(self)) { return; } // Sicherheitscheck falls oben gestorben

        if (energy <= 0 and waittime = 0) {
            // NetLogo Conditions: Anzahl < Limit AND pcolor = 53 AND Befall = false
            if (my_cell.Anzahl < Beetleonpatch and my_cell.Baumart = "1" and !my_cell.Befall) {
                
                waittime <- 1;
                
                if (lifecount = 0) {
                    lifecount <- 1;
                    do vermehren; 
                    energy <- rnd(21) + 5;
                    if (rnd(100.0) < 33) { do die; } // Float fix
                    
                } else if (lifecount = 1) {
                    do vermehren2;
                    do die;
                }
            }
        }
    }

    action vermehren {
        forest_cell my_cell <- forest_cell(location);
        
        if (my_cell.pheromon) {
            my_cell.Eier <- 7.0;
            my_cell.Befallszahl <- my_cell.Befallszahl + 1;
            ask my_cell { do check_befall_threshold; }
        } 
        else {
            bool high_pressure <- maxbeetlechecker or length(beetle) > maxbeetles;
            
            if (high_pressure) {
                if (rnd(100) < 30) { 
                    my_cell.pheromon <- true;
                    my_cell.Eier <- 7.0;
                    my_cell.Befallszahl <- my_cell.Befallszahl + 1;
                    ask my_cell { do check_befall_threshold; }
                } else {
                    do die;
                }
            } 
            else {
                if (rnd(100) < 35) {
                    if (rnd(100) < 25) {
                        my_cell.pheromon <- true;
                        my_cell.Eier <- 7.0;
                        my_cell.Befallszahl <- my_cell.Befallszahl + 1;
                        ask my_cell { do check_befall_threshold; }
                    } else {
                        do die;
                    }
                } 
                else {
                    my_cell.Eier3 <- 7.0;
                    my_cell.Befallszahl3 <- my_cell.Befallszahl3 + 1;
                    ask my_cell { do check_befall_threshold; }
                }
            }
        }
    }
    
    action vermehren2 {
        forest_cell my_cell <- forest_cell(location);
        
        if (my_cell.pheromon) {
            my_cell.Eier2 <- 7.0;
            my_cell.Befallszahl2 <- my_cell.Befallszahl2 + 1;
            ask my_cell { do check_befall_threshold; }
        } 
        else {
            bool high_pressure <- maxbeetlechecker or length(beetle) > maxbeetles;
            
            if (high_pressure) {
                if (rnd(100) < 30) { 
                    my_cell.pheromon <- true;
                    my_cell.Eier2 <- 7.0;
                    my_cell.Befallszahl2 <- my_cell.Befallszahl2 + 1;
                    ask my_cell { do check_befall_threshold; }
                } else {
                    do die;
                }
            } 
            else {
                if (rnd(100) < 35) {
                    if (rnd(100) < 25) {
                        my_cell.pheromon <- true;
                        my_cell.Eier2 <- 7.0;
                        my_cell.Befallszahl2 <- my_cell.Befallszahl2 + 1;
                        ask my_cell { do check_befall_threshold; }
                    } else {
                        do die;
                    }
                } 
                else {
                    my_cell.Eier4 <- 7.0;
                    my_cell.Befallszahl4 <- my_cell.Befallszahl4 + 1;
                    ask my_cell { do check_befall_threshold; }
                }
            }
        }
    }
}

experiment Borkenkaefer_Final type: gui {
    output {
        display Map type: opengl {
            grid forest_cell border: #transparent;
            species beetle aspect: default;
        }
        
        display Graphs {
            // GRAPH 1: Population
            chart "Population" type: series size: {1.0, 0.5} position: {0, 0} {
                data "Beetles" value: length(beetle) color: #red;
                data "Temp x 100" value: temp * 100 color: #blue;
            }
            // GRAPH 2: Totholz (Neu!)
            chart "Wood Damage" type: series size: {1.0, 0.5} position: {0, 0.5} {
                data "Damage (m3)" value: maxbefall color: #black;
            }
        }
        
        monitor "Year" value: year;
        monitor "Month" value: month;
        monitor "Tick" value: tick_counter;
        monitor "Temperature" value: temp with_precision 2;
        monitor "Beetles" value: length(beetle);
        monitor "Should Move?" value: (month >= 3 and month <= 7 and temp >= 16);
        monitor "Moved This Cycle" value: beetles_moved_this_cycle;
        monitor "Winter Deaths" value: winter_deaths_this_cycle;
    }
}


// --- BATCH EXPERIMENT FÜR VALIDIERUNG ---
experiment Validation_Batch type: batch repeat: 10 keep_seed: false until: (cycle >= 8400) {
    
    // Parameter überschreiben für den Batch-Lauf
    parameter "Batch Mode Aktivieren" var: is_batch <- true;
    parameter "Exact Port Mode" var: exact_port_mode <- true;

    // Einmalige Initialisierung: Datei leeren und Header schreiben
    init {
        save ["run_id", "step", "beetles", "wood_damage"] 
             to: "../results/gama_results.csv" format: "csv" rewrite: true;
    }
}
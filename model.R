
#!/usr/bin/env Rscript

suppressMessages({
  library(readxl)
  library(forecast)
  library(dplyr)
  library(zoo)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("Usage: Rscript model.R input.xlsx output_dir [sheet]")
DATA_PATH <- args[1]
OUT_DIR <- args[2]
SHEET_NAME <- ifelse(length(args) >= 3, args[3], "Donnees_Completes")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)
N_SIMULATIONS <- 10000
FORECAST_HORIZON <- 2

EVENT_PARAMS <- list(
  "800 m" = list(ventilation=c(70,128.8,210), duree=c(3.67,4.335,5.67)),
  "1500 m" = list(ventilation=c(70,122.5,195), duree=c(3.88,4.375,6.67)),
  "2000 m steeple" = list(ventilation=c(70,121.3,190), duree=c(5.58,6.33,7.33)),
  "3000 m" = list(ventilation=c(65,112.5,180), duree=c(8.13,9.21,11.58)),
  "5000 m marche" = list(ventilation=c(40,78.8,135), duree=c(20.25,22.75,25.83))
)

NIVEAU_ACTION <- list(
  "Faible|Faible"=list(niveau=1, action="Routine"),
  "Faible|Elevee"=list(niveau=2, action="Vigilance - exposition liee a l'effort"),
  "Moderee|Faible"=list(niveau=2, action="Vigilance"),
  "Moderee|Elevee"=list(niveau=3, action="Precaution renforcee"),
  "Elevee|Faible"=list(niveau=3, action="Precaution renforcee"),
  "Elevee|Elevee"=list(niveau=3, action="Precaution renforcee")
)

rtriangular <- function(n,a,c,b) {
  if (b <= a) return(rep(a,n))
  c <- min(max(c,a),b)
  u <- runif(n); Fc <- (c-a)/(b-a)
  ifelse(u < Fc, a+sqrt(u*(b-a)*(c-a)),
         b-sqrt((1-u)*(b-a)*(b-c)))
}

load_data <- function(path, sheet) {
  df <- read_excel(path, sheet=sheet)
  required <- c("Date","TC","HR","PM10")
  missing <- setdiff(required, names(df))
  if (length(missing)) stop(paste("Colonnes manquantes:", paste(missing, collapse=", ")))
  df$Date <- as.Date(df$Date)
  df <- df[order(df$Date),]
  full_dates <- seq(min(df$Date),max(df$Date),by="day")
  if (length(full_dates) != nrow(df) || anyDuplicated(df$Date)) {
    df <- data.frame(Date=full_dates) %>%
      left_join(df,by="Date") %>%
      mutate(across(c(TC,HR,PM10),~zoo::na.approx(.x,na.rm=FALSE)))
  }
  df <- df %>% tidyr::drop_na(TC,HR,PM10)
  df
}

forecast_exog_series <- function(x,steps=2) {
  fit <- auto.arima(ts(x,frequency=7),seasonal=TRUE,stepwise=FALSE,approximation=FALSE)
  fc <- forecast(fit,h=steps)
  list(mean=as.numeric(fc$mean), model=fit)
}

fit_PM10_model <- function(endog,exog) {
  auto.arima(endog,xreg=exog,seasonal=FALSE,stepwise=FALSE,approximation=FALSE)
}

forecast_PM10 <- function(fit,xreg_future,level=95) {
  fc <- forecast(fit,xreg=xreg_future,level=level)
  mean_fc <- as.numeric(fc$mean)
  lower95 <- as.numeric(fc$lower[,1])
  upper95 <- as.numeric(fc$upper[,1])
  se <- pmax((upper95-mean_fc)/qnorm(.975),0)
  data.frame(
    PM10_forecast_mean=mean_fc,
    CI_lower_95=pmax(lower95,0),
    CI_upper_95=pmax(upper95,0),
    P25=pmax(mean_fc+qnorm(.25)*se,0),
    P50=pmax(mean_fc,0),
    P95=pmax(mean_fc+qnorm(.95)*se,0)
  )
}

classify_concentration <- function(p50) {
  if (p50 <= 15) "Faible" else if (p50 <= 25) "Moderee" else "Elevee"
}
classify_dose <- function(p50) ifelse(p50 <= 15,"Faible","Elevee")

simulate_dose <- function(p25,p50,p95,ventilation_params,duree_params,n_sim=10000) {
  ord <- sort(c(p25,p50,p95))
  conc <- rtriangular(n_sim,ord[1],ord[2],ord[3])
  vent <- rtriangular(n_sim,ventilation_params[1],ventilation_params[2],ventilation_params[3])
  dur <- rtriangular(n_sim,duree_params[1],duree_params[2],duree_params[3])
  conc*vent*dur*.001
}

build_classification_table <- function(fc) {
  rows <- list(); idx <- 1
  for(i in seq_len(nrow(fc))) {
    conc_class <- classify_concentration(fc$P50[i])
    for(event in names(EVENT_PARAMS)) {
      p <- EVENT_PARAMS[[event]]
      d <- simulate_dose(fc$P25[i],fc$P50[i],fc$P95[i],p$ventilation,p$duree,N_SIMULATIONS)
      q <- quantile(d,c(.25,.5,.95),names=TRUE)
      dose_class <- classify_dose(as.numeric(q[2]))
      key <- paste0(conc_class,"|",dose_class)
      na <- NIVEAU_ACTION[[key]]
      rows[[idx]] <- data.frame(
        Day=fc$Day[i], Event=event,
        PM10_P25=round(fc$P25[i],2), PM10_P50=round(fc$P50[i],2), PM10_P95=round(fc$P95[i],2),
        Classification_concentration_PM10=conc_class,
        Dose_inhalee_P25_mg=round(as.numeric(q[1]),3),
        Dose_inhalee_P50_mg=round(as.numeric(q[2]),3),
        Dose_inhalee_P95_mg=round(as.numeric(q[3]),3),
        Classification_dose_inhalee=dose_class,
        Niveau_provisoire=na$niveau, Action=na$action,
        stringsAsFactors=FALSE
      )
      idx <- idx+1
    }
  }
  do.call(rbind,rows)
}

df <- load_data(DATA_PATH,SHEET_NAME)
tc <- forecast_exog_series(df$TC)
hr <- forecast_exog_series(df$HR)
future_dates <- seq(max(df$Date)+1,by="day",length.out=FORECAST_HORIZON)
xreg_future <- cbind(TC=tc$mean,HR=hr$mean)
fit <- fit_PM10_model(df$PM10,cbind(TC=df$TC,HR=df$HR))
fc <- forecast_PM10(fit,xreg_future)
fc <- cbind(Date=future_dates,Day=c("J+1","J+2"),fc)
class_table <- build_classification_table(fc)

write.csv(fc,file.path(OUT_DIR,"PM10_forecast.csv"),row.names=FALSE)
write.csv(class_table,file.path(OUT_DIR,"exposure_classification.csv"),row.names=FALSE)

summary <- list(
  observations=nrow(df),
  date_start=as.character(min(df$Date)),
  date_end=as.character(max(df$Date)),
  model=as.character(fit),
  tc_forecast=round(tc$mean,3),
  hr_forecast=round(hr$mean,3),
  simulations=N_SIMULATIONS
)
jsonlite::write_json(summary,file.path(OUT_DIR,"summary.json"),auto_unbox=TRUE,pretty=TRUE)
cat("SUCCESS\n")

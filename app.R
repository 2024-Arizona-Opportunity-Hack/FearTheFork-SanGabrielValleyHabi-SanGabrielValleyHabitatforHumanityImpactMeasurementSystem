# app.R

# Load required libraries
library(shiny)
library(shinythemes)
library(shinyWidgets)
library(shinydashboard) # For box() function
library(shinycssloaders)
library(readxl) # For reading Excel files
library(dplyr)
library(ggplot2)
library(corrplot)
library(car)
library(DT)

# Define UI for application
ui <- fluidPage(
  theme = shinytheme("cosmo"),
  
  # Application title
  titlePanel("Automated Multiple Regression Analysis"),
  
  sidebarLayout(
    sidebarPanel(
      # File input for uploading Excel or CSV file
      fileInput("file", "Upload Data File", 
                accept = c(".xlsx", ".csv")),
      
      # Conditional panel: Show only after file is uploaded
      conditionalPanel(
        condition = "output.fileUploaded == true",
        # Dropdown to select dependent variable
        uiOutput("dep_var_ui"),
        
        # Button to initiate analysis
        actionButton("analyze", "Run Regression Analysis")
      ),
      width = 3
    ),
    
    mainPanel(
      tabsetPanel(
        tabPanel("Data Overview",
                 DTOutput("data_table") %>% withSpinner()
        ),
        tabPanel("EDA",
                 fluidRow(
                   box(title = "Summary Statistics", status = "primary", solidHeader = TRUE, 
                       verbatimTextOutput("data_summary"))
                 ),
                 fluidRow(
                   box(title = "Histogram", status = "primary", solidHeader = TRUE, 
                       plotOutput("hist_plot") %>% withSpinner())
                 ),
                 fluidRow(
                   box(title = "Boxplot", status = "primary", solidHeader = TRUE, 
                       plotOutput("box_plot") %>% withSpinner())
                 )
        ),
        tabPanel("Correlation Analysis",
                 fluidRow(
                   box(title = "Correlation Matrix", status = "primary", solidHeader = TRUE, 
                       plotOutput("corr_plot") %>% withSpinner())
                 ),
                 fluidRow(
                   box(title = "Selected Variables Based on Correlation", status = "primary", solidHeader = TRUE, 
                       DTOutput("selected_vars_table"))
                 )
        ),
        tabPanel("Regression Models",
                 fluidRow(
                   box(title = "Model Summary", status = "primary", solidHeader = TRUE, 
                       verbatimTextOutput("model_summary") %>% withSpinner())
                 ),
                 fluidRow(
                   box(title = "ANOVA Results", status = "primary", solidHeader = TRUE, 
                       verbatimTextOutput("anova_results") %>% withSpinner())
                 )
        ),
        tabPanel("Multicollinearity",
                 fluidRow(
                   box(title = "VIF Values", status = "primary", solidHeader = TRUE, 
                       verbatimTextOutput("vif_values") %>% withSpinner())
                 ),
                 fluidRow(
                   box(title = "High VIF Variables", status = "warning", solidHeader = TRUE, 
                       verbatimTextOutput("high_vif") %>% withSpinner())
                 )
        ),
        tabPanel("Final Model",
                 fluidRow(
                   box(title = "Final Regression Model Summary", status = "primary", solidHeader = TRUE, 
                       verbatimTextOutput("final_model_summary") %>% withSpinner())
                 ),
                 fluidRow(
                   box(title = "Regression Equation", status = "primary", solidHeader = TRUE, 
                       verbatimTextOutput("regression_eq") %>% withSpinner())
                 )
        )
      )
    )
  )
)

# Define server logic required for the application
server <- function(input, output, session) {
  
  # Reactive expression to check if file is uploaded
  output$fileUploaded <- reactive({
    return(!is.null(input$file))
  })
  outputOptions(output, 'fileUploaded', suspendWhenHidden=FALSE)
  
  # Reactive expression to read the uploaded data
  uploaded_data <- reactive({
    req(input$file)
    tryCatch({
      ext <- tools::file_ext(input$file$name)
      if (ext == "csv") {
        df <- read.csv(input$file$datapath, stringsAsFactors = FALSE)
      } else if (ext %in% c("xls", "xlsx")) {
        df <- read_excel(input$file$datapath)
      } else {
        showNotification("Unsupported file type. Please upload a .csv or .xlsx file.", type = "error")
        return(NULL)
      }
      return(df)
    }, error = function(e) {
      showNotification("Error in reading the file. Please ensure it's a valid CSV or Excel file.", type = "error")
      return(NULL)
    })
  })
  
  # Display the data in a table
  output$data_table <- renderDT({
    req(uploaded_data())
    datatable(uploaded_data(), options = list(pageLength = 10, scrollX = TRUE))
  })
  
  # UI for selecting dependent variable
  output$dep_var_ui <- renderUI({
    req(uploaded_data())
    df <- uploaded_data()
    numeric_vars <- names(df)[sapply(df, is.numeric)]
    if(length(numeric_vars) == 0){
      return(NULL)
    }
    # Set default selected variable to "Target" if exists, else first numeric variable
    default_dep_var <- if("Target" %in% numeric_vars) {
      "Target"
    } else {
      numeric_vars[1]
    }
    selectInput("dep_var", "Select Dependent Variable:", 
                choices = numeric_vars,
                selected = default_dep_var)
  })
  
  # Reactive values
  selected_vars <- reactiveVal(character(0))
  model_data_selected <- reactiveVal(NULL)
  
  # Event listener for the Analyze button
  observeEvent(input$analyze, {
    req(uploaded_data(), input$dep_var)
    
    df <- uploaded_data()
    dep_var <- input$dep_var
    
    # Preprocessing
    # Convert character variables to factors
    df <- df %>% mutate(across(where(is.character), as.factor))
    
    # Handle missing values by removing rows with NA in dependent variable
    df <- df %>% filter(!is.na(.data[[dep_var]]))
    
    # Identify columns to exclude (e.g., identifying information)
    excluded_columns <- c("Applicant's Full Name","Street Address:","Best Phone Number:",
                          "Contact's Best Phone number:","Contact's Email Address:")
    
    # Ensure excluded columns exist in the dataset
    excluded_columns <- intersect(excluded_columns, names(df))
    
    # Select predictors by excluding specified columns
    predictors <- df %>% select(-all_of(excluded_columns))
    
    # Identify and remove categorical predictors with only one level
    categorical_vars <- names(predictors)[sapply(predictors, is.factor)]
    single_level_vars <- categorical_vars[sapply(predictors[categorical_vars], function(x) length(levels(x)) < 2)]
    
    if(length(single_level_vars) > 0){
      predictors <- predictors %>% select(-all_of(single_level_vars))
      showNotification(paste("Removed categorical variables with only one level:", 
                             paste(single_level_vars, collapse = ", ")), type = "warning")
    }
    
    # If no predictors left, notify the user
    if(ncol(predictors) == 0){
      showNotification("No predictor variables available for regression after preprocessing.", type = "error")
      return(NULL)
    }
    
    # Create dummy variables for remaining categorical predictors
    dummy_vars <- model.matrix(~ ., data = predictors)[,-1]
    
    # Combine dependent variable with dummy variables
    model_data <- cbind(df[[dep_var]], dummy_vars)
    colnames(model_data)[1] <- dep_var
    
    # Convert to data frame
    model_data <- as.data.frame(model_data)
    
    # Ensure there are enough observations
    if(nrow(model_data) < 2){
      showNotification("Not enough observations for regression analysis. Please provide at least two.", type = "error")
      return(NULL)
    }
    
    # Calculate correlation with dependent variable
    cor_matrix <- cor(model_data, use = "complete.obs")
    cor_with_dep <- cor_matrix[dep_var, ]
    cor_with_dep_abs <- abs(cor_with_dep)
    
    # Select variables with correlation > 0.3 (threshold can be adjusted)
    threshold <- 0.3
    selected <- names(cor_with_dep_abs[cor_with_dep_abs > threshold & names(cor_with_dep_abs) != dep_var])
    
    if(length(selected) == 0){
      showNotification("No predictor variables exceed the correlation threshold. Consider lowering the threshold.", type = "warning")
    }
    
    # Update selected_vars reactive value
    selected_vars(as.character(selected))
    
    # Update model_data_selected reactive value
    model_data_selected(model_data[, c(dep_var, selected), drop = FALSE])
  })
  
  # Display summary statistics
  output$data_summary <- renderPrint({
    req(selected_vars(), model_data_selected())
    summary(model_data_selected())
  })
  
  # Display histogram of dependent variable
  output$hist_plot <- renderPlot({
    req(selected_vars(), model_data_selected())
    dep_var <- input$dep_var
    ggplot(model_data_selected(), aes_string(x = dep_var)) +
      geom_histogram(fill = "steelblue", color = "black", bins = 30) +
      theme_minimal() +
      labs(title = paste("Histogram of", dep_var),
           x = dep_var,
           y = "Frequency")
  })
  
  # Display boxplot of dependent variable
  output$box_plot <- renderPlot({
    req(selected_vars(), model_data_selected())
    dep_var <- input$dep_var
    ggplot(model_data_selected(), aes_string(y = dep_var)) +
      geom_boxplot(fill = "orange") +
      theme_minimal() +
      labs(title = paste("Boxplot of", dep_var),
           y = dep_var)
  })
  
  # Display correlation matrix
  output$corr_plot <- renderPlot({
    req(selected_vars(), model_data_selected())
    # Only include numeric variables for correlation plot
    numeric_data <- model_data_selected() %>% select(where(is.numeric))
    corr_matrix <- cor(numeric_data, use = "complete.obs")
    corrplot(corr_matrix, method = "color", type = "upper",
             tl.col = "black", tl.srt = 45, addCoef.col = "black",
             number.cex = 0.7, title = "Correlation Matrix", mar = c(0,0,1,0))
  })
  
  # Display selected variables based on correlation
  output$selected_vars_table <- renderDT({
    req(selected_vars(), model_data_selected())
    dep_var <- input$dep_var
    selected <- selected_vars()
    if(length(selected) == 0){
      return(NULL)
    }
    df_corr <- cor(model_data_selected())
    df_corr <- as.data.frame(df_corr[dep_var, selected])
    df_corr <- df_corr %>% 
      mutate(Variable = rownames(df_corr)) %>% 
      select(Variable, Correlation = 1) %>% 
      arrange(desc(abs(Correlation)))
    datatable(df_corr, options = list(pageLength = 10, scrollX = TRUE))
  })
  
  # Display regression model summary
  output$model_summary <- renderPrint({
    req(selected_vars(), model_data_selected())
    dep_var <- input$dep_var
    selected <- selected_vars()
    
    # Check if there are selected predictors
    if(length(selected) == 0){
      cat("No predictor variables selected based on the correlation threshold.")
      return(NULL)
    }
    
    # Build formula with selected variables
    formula_str <- paste(dep_var, "~", paste(selected, collapse = " + "))
    formula <- as.formula(formula_str)
    
    # Fit the model
    model <- lm(formula, data = model_data_selected())
    summary(model)
  })
  
  # Display ANOVA results
  output$anova_results <- renderPrint({
    req(selected_vars(), model_data_selected())
    dep_var <- input$dep_var
    selected <- selected_vars()
    
    # Check if there are selected predictors
    if(length(selected) == 0){
      cat("No predictor variables selected based on the correlation threshold.")
      return(NULL)
    }
    
    # Build formula with selected variables
    formula_str <- paste(dep_var, "~", paste(selected, collapse = " + "))
    formula <- as.formula(formula_str)
    
    # Fit the model
    model <- lm(formula, data = model_data_selected())
    
    # Perform ANOVA
    anova(model)
  })
  
  # Display VIF values
  output$vif_values <- renderPrint({
    req(selected_vars(), model_data_selected())
    dep_var <- input$dep_var
    selected <- selected_vars()
    
    # Check if there are selected predictors
    if(length(selected) == 0){
      cat("No predictor variables selected based on the correlation threshold.")
      return(NULL)
    }
    
    # Build formula with selected variables
    formula_str <- paste(dep_var, "~", paste(selected, collapse = " + "))
    formula <- as.formula(formula_str)
    model <- lm(formula, data = model_data_selected())
    vif_vals <- vif(model)
    print(vif_vals)
  })
  
  # Display variables with high VIF
  output$high_vif <- renderPrint({
    req(selected_vars(), model_data_selected())
    dep_var <- input$dep_var
    selected <- selected_vars()
    
    # Check if there are selected predictors
    if(length(selected) == 0){
      cat("No predictor variables selected based on the correlation threshold.")
      return(NULL)
    }
    
    # Build formula with selected variables
    formula_str <- paste(dep_var, "~", paste(selected, collapse = " + "))
    formula <- as.formula(formula_str)
    model <- lm(formula, data = model_data_selected())
    vif_vals <- vif(model)
    high_vif <- vif_vals[vif_vals > 5]
    if(length(high_vif) > 0){
      cat("Variables with VIF > 5 indicating multicollinearity:\n")
      print(high_vif)
    } else {
      cat("No multicollinearity detected (All VIF <= 5).\n")
    }
  })
  
  # Display final regression model summary after removing multicollinear variables
  output$final_model_summary <- renderPrint({
    req(selected_vars(), model_data_selected())
    dep_var <- input$dep_var
    selected <- selected_vars()
    
    # Check if there are selected predictors
    if(length(selected) == 0){
      cat("No predictor variables selected based on the correlation threshold.")
      return(NULL)
    }
    
    # Initialize the model
    formula_str <- paste(dep_var, "~", paste(selected, collapse = " + "))
    formula <- as.formula(formula_str)
    model <- lm(formula, data = model_data_selected())
    
    # Iteratively remove variables with VIF > 5
    while(any(vif(model) > 5)){
      high_vif_var <- names(which.max(vif(model)))
      selected <- selected[!selected %in% high_vif_var]
      selected_vars(selected)
      if(length(selected) == 0){
        break
      }
      formula_str <- paste(dep_var, "~", paste(selected, collapse = " + "))
      formula <- as.formula(formula_str)
      model <- lm(formula, data = model_data_selected())
    }
    
    if(length(selected) == 0){
      cat("All variables have been removed due to high multicollinearity.")
    } else {
      summary(model)
    }
  })
  
  # Display final regression equation
  output$regression_eq <- renderPrint({
    req(selected_vars(), model_data_selected())
    dep_var <- input$dep_var
    selected <- selected_vars()
    
    # Check if there are selected predictors
    if(length(selected) == 0){
      cat("No final model available due to high multicollinearity.")
      return(NULL)
    }
    
    # Initialize the model
    formula_str <- paste(dep_var, "~", paste(selected, collapse = " + "))
    formula <- as.formula(formula_str)
    model <- lm(formula, data = model_data_selected())
    
    # Iteratively remove variables with highest VIF > 5
    while(any(vif(model) > 5)){
      high_vif_var <- names(which.max(vif(model)))
      selected <- selected[!selected %in% high_vif_var]
      selected_vars(selected)
      if(length(selected) == 0){
        break
      }
      formula_str <- paste(dep_var, "~", paste(selected, collapse = " + "))
      formula <- as.formula(formula_str)
      model <- lm(formula, data = model_data_selected())
    }
    
    if(length(selected) == 0){
      cat("No final model available due to high multicollinearity.")
    } else {
      # Extract coefficients
      coefs <- coef(model)
      vars <- names(coefs)
      
      # Construct equation string
      eq <- paste(dep_var, " = ", round(coefs[1], 3), sep = "")
      for(i in 2:length(coefs)){
        sign <- ifelse(coefs[i] >= 0, "+", "-")
        eq <- paste(eq, sign, " ", abs(round(coefs[i], 3)), " * ", vars[i], sep = "")
      }
      
      cat("Final Regression Equation:\n")
      cat(eq)
    }
  })
}

# Run the application 
shinyApp(ui = ui, server = server)
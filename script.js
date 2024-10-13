// script.js

let parsedData = [];
let headers = [];

// Function to parse CSV
function parseCSV(csv) {
    const lines = csv.trim().split('\n');
    headers = lines[0].split(',');
    parsedData = lines.slice(1).map(line => {
        const values = line.split(',');
        let obj = {};
        headers.forEach((header, index) => {
            obj[header.trim()] = values[index].trim();
        });
        return obj;
    });
}

// Function to handle file upload and read CSV
function processData() {
    const fileInput = document.getElementById('csvFile');
    if (!fileInput.files.length) {
        alert("Please upload a CSV file.");
        return;
    }

    const file = fileInput.files[0];
    const reader = new FileReader();

    reader.onload = function(e) {
        const text = e.target.result;
        parseCSV(text);
        analyzeAndVisualize();
    };

    reader.readAsText(file);
}

// Function to analyze data and create visualizations
function analyzeAndVisualize() {
    // Example Correlations:
    // 1. Frequency vs Importance
    // 2. Category vs Rating
    // 3. Numerical Value vs Assistance Type

    // Convert categorical data to numerical for correlation
    const frequencyMap = {'Always': 4, 'Often': 3, 'Sometimes': 2, 'Rarely': 1, 'Never': 0};
    const importanceMap = {'very important': 3, 'slightly important': 2, 'very unimportant': 0, 'slightly unimportant':1};

    let frequency = [];
    let importance = [];
    let numericalValues = [];

    parsedData.forEach(row => {
        frequency.push(frequencyMap[row[headers[1]]] || 0);
        importance.push(importanceMap[row[headers[6]]] || 0);
        numericalValues.push(parseInt(row[headers[14]]) || 0);
    });

    // 1. Frequency vs Importance Scatter Plot
    let scatterTrace = {
        x: frequency,
        y: importance,
        mode: 'markers',
        type: 'scatter',
        marker: { size: 12, color: 'rgba(152, 0, 0, .8)' },
        text: parsedData.map(row => row[headers[0]]),
        name: 'Frequency vs Importance'
    };

    let scatterLayout = {
        title: 'Frequency vs Importance',
        xaxis: { title: headers[1] },
        yaxis: { title: headers[6] }
    };

    Plotly.newPlot('scatterPlot', [scatterTrace], scatterLayout);

    // 2. Frequency and Importance Heatmap
    // Create a correlation matrix
    let corrMatrix = computeCorrelationMatrix([frequency, importance, numericalValues]);

    let heatmapTrace = {
        z: corrMatrix,
        x: ['Frequency', 'Importance', 'Numerical Value'],
        y: ['Frequency', 'Importance', 'Numerical Value'],
        type: 'heatmap',
        colorscale: 'Viridis'
    };

    let heatmapLayout = {
        title: 'Correlation Heatmap',
        xaxis: { ticks: '', side: 'top' },
        yaxis: { ticks: '', ticksuffix: ' ' }
    };

    Plotly.newPlot('heatmap', [heatmapTrace], heatmapLayout);

    // 3. Bar Chart of Assistance Types
    let assistanceCounts = {};
    parsedData.forEach(row => {
        let assistance = row[headers[15]];
        assistanceCounts[assistance] = (assistanceCounts[assistance] || 0) + 1;
    });

    let barTrace = {
        x: Object.keys(assistanceCounts),
        y: Object.values(assistanceCounts),
        type: 'bar',
        marker: { color: 'rgb(142,124,195)' }
    };

    let barLayout = {
        title: 'Assistance Types Distribution',
        xaxis: { title: 'Assistance Type' },
        yaxis: { title: 'Count' }
    };

    Plotly.newPlot('barChart', [barTrace], barLayout);
}

// Function to compute correlation matrix
function computeCorrelationMatrix(dataArrays) {
    let matrix = [];
    for (let i = 0; i < dataArrays.length; i++) {
        let row = [];
        for (let j = 0; j < dataArrays.length; j++) {
            if (i === j) {
                row.push(1);
            } else {
                row.push(correlation(dataArrays[i], dataArrays[j]).toFixed(2));
            }
        }
        matrix.push(row);
    }
    return matrix;
}

// Function to calculate Pearson correlation coefficient
function correlation(x, y) {
    let n = x.length;
    let sum_x = 0, sum_y = 0, sum_xy = 0;
    let sum_x2 = 0, sum_y2 = 0;

    for(let i =0; i < n; i++) {
        sum_x += x[i];
        sum_y += y[i];
        sum_xy += (x[i] * y[i]);
        sum_x2 += (x[i] * x[i]);
        sum_y2 += (y[i] * y[i]);
    }

    let numerator = (n * sum_xy) - (sum_x * sum_y);
    let denominator = Math.sqrt( (n * sum_x2 - sum_x * sum_x) * (n * sum_y2 - sum_y * sum_y) );

    if(denominator === 0) return 0;

    return numerator / denominator;
}
const express = require('express');
const fs = require('fs').promises;
const app = express();

// Middleware to parse JSON
app.use(express.json());

// Home page with build history table
app.get('/', async (req, res) => {
    try {
        const builds = await fs.readFile('/var/www/builds.json', 'utf8');
        const buildData = JSON.parse(builds);
        let table = '<h1>Build History</h1><table border="1"><tr><th>Build #</th><th>Status</th><th>Who Ran It</th><th>Duration (seconds)</th></tr>';
        buildData.forEach(build => {
            table += `<tr><td>${build.buildNumber}</td><td>${build.status}</td><td>${build.whoRan}</td><td>${build.duration}</td></tr>`;
        });
        table += '</table>';
        res.send(table);
    } catch (err) {
        res.send('<h1>Hello from Jenkins and NGINX!</h1>');
    }
});

// Status page (unchanged)
app.get('/status', async (req, res) => {
    try {
        const status = await fs.readFile('/var/www/status.txt', 'utf8');
        const color = status.trim() === 'SUCCESS' ? 'green' : 'red';
        res.send(`
            <html><body><h1>Build Status</h1><p>Current Status: <span style="font-weight: bold; color: ${color}">${status.trim()}</span></p></body></html>
        `);
    } catch (err) {
        res.send('<h1>Status Unavailable</h1>');
    }
});

app.listen(80, () => console.log('App on port 80'));

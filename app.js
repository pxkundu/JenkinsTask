const express = require('express');
const fs = require('fs').promises;
const app = express();

app.get('/', (req, res) => res.send('Hello from Jenkins CI/CD!'));
app.get('/status', async (req, res) => {
    try {
        const status = await fs.readFile('/var/www/status.txt', 'utf8');
        const color = status.trim() === 'SUCCESS' ? 'green' : 'red';
        res.send(`
            <html>
                <body>
                    <h1>Build Status</h1>
                    <p>Current Status: <span style="font-weight: bold; color: ${color}">${status.trim()}</span></p>
                </body>
            </html>
        `);
    } catch (err) {
        res.send('<h1>Status Unavailable</h1>');
    }
});

app.listen(80, () => console.log('App on port 80'));

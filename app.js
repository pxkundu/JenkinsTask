const express = require('express');
const app = express();
app.get('/', (req, res) => res.send('Hello from Jenkins CI/CD!'));
app.listen(80, () => console.log('App on port 80'));

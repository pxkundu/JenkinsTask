const express = require('express');
const app = express();
app.use(express.json());
let tasks = [];

app.post('/tasks', (req, res) => {
  tasks.push(req.body);
  res.status(201).send(req.body);
});

app.get('/tasks', (req, res) => res.send(tasks));
app.listen(5000, () => console.log('Backend on port 5000'));

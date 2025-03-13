const http = require('http');
const server = http.createServer((req, res) => {
    res.statusCode = 200;
    res.setHeader('Content-Type', 'text/plain');
    res.end('Hello from Jenkins and Node.js!');
});
server.listen(80, () => {
    console.log('Server running on port 80');
});

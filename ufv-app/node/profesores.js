const express = require('express');
const { Pool } = require('pg');

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const pool = new Pool({
    host: '10.0.1.10' || 'localhost',
    user: 'backend',
    password: 'ContraseñaSegura123',
    database: 'academico',
    port: 5432
});

const getBaseHTML = (title, content) => `
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>${title}</title>
    <link rel="stylesheet" href="/static/css/style.css">
</head>
<body>
    <div class="container">
        <img src="/static/img/logo.png" alt="Logo" class="logo">
        <h1>${title}</h1>
        <div class="nav">
            <a href="/">🏠 Inicio</a> | 
            <a href="/profesores/asignaturas">📚 Asignaturas</a> | 
            <a href="/profesores/asignaturas/nueva">➕ Nueva</a>
        </div>
        <hr>
        ${content}
        <div class="footer">Panel de Profesores - Nodo: ${process.env.HOSTNAME || 'Desconocido'}</div>
    </div>
</body>
</html>
`;

app.get('/profesores/asignaturas', async (req, res) => {
    try {
        const result = await pool.query('SELECT * FROM academico.asignaturas ORDER BY id');
        let html = '<table><tr><th>ID</th><th>Nombre</th><th>Créditos</th><th>Acciones</th></tr>';
        result.rows.forEach(r => {
            html += `<tr>
                <td>${r.id}</td>
                <td>${r.nombre}</td>
                <td>${r.creditos}</td>
                <td>
                    <a href="/profesores/asignaturas/editar/${r.id}">✏️</a> | 
                    <a href="/profesores/asignaturas/borrar/${r.id}" onclick="return confirm('¿Seguro?')">🗑️</a>
                </td>
            </tr>`;
        });
        html += '</table>';
        res.send(getBaseHTML("Gestión de Asignaturas", html));
    } catch (err) { res.status(500).send(err.message); }
});

app.get('/profesores/asignaturas/nueva', (req, res) => {
    const form = `
        <form action="/profesores/asignaturas" method="POST">
            <input type="text" name="nombre" placeholder="Nombre" required>
            <textarea name="descripcion" placeholder="Descripción"></textarea>
            <input type="number" name="creditos" placeholder="Créditos" required>
            <button type="submit">Guardar</button>
        </form>`;
    res.send(getBaseHTML("Nueva Asignatura", form));
});

app.post('/profesores/asignaturas', async (req, res) => {
    const { nombre, descripcion, creditos } = req.body;
    try {
        await pool.query('INSERT INTO academico.asignaturas(nombre, descripcion, creditos) VALUES($1, $2, $3)', [nombre, descripcion, creditos]);
        res.redirect('/profesores/asignaturas');
    } catch (err) { res.status(500).send(err.message); }
});

app.get('/profesores/asignaturas/editar/:id', async (req, res) => {
    try {
        const result = await pool.query('SELECT * FROM academico.asignaturas WHERE id = $1', [req.params.id]);
        const r = result.rows[0];
        const form = `
            <form action="/profesores/asignaturas/update" method="POST">
                <input type="hidden" name="id" value="${r.id}">
                <input type="text" name="nombre" value="${r.nombre}" required>
                <textarea name="descripcion">${r.descripcion}</textarea>
                <input type="number" name="creditos" value="${r.creditos}" required>
                <button type="submit">Actualizar</button>
            </form>`;
        res.send(getBaseHTML("Editar Asignatura", form));
    } catch (err) { res.status(500).send(err.message); }
});

app.post('/profesores/asignaturas/update', async (req, res) => {
    const { id, nombre, descripcion, creditos } = req.body;
    try {
        await pool.query('UPDATE academico.asignaturas SET nombre=$1, descripcion=$2, creditos=$3 WHERE id=$4', [nombre, descripcion, creditos, id]);
        res.redirect('/profesores/asignaturas');
    } catch (err) { res.status(500).send(err.message); }
});

app.get('/profesores/asignaturas/borrar/:id', async (req, res) => {
    try {
        await pool.query('DELETE FROM academico.asignaturas WHERE id = $1', [req.params.id]);
        res.redirect('/profesores/asignaturas');
    } catch (err) { res.status(500).send(err.message); }
});

app.listen(3001, '0.0.0.0', () => console.log("Servidor profesores en puerto 3001"));

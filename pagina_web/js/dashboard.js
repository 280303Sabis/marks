/*
  dashboard.js - Panel del administrador (dashboard.html)
  --------------------------------------------------------
  1. Protege la página: sin sesión de ADMIN regresa a index.html.
  2. Hace funcionar el botón "Cerrar Sesión".
  (Los datos reales del panel se conectarán en pasos siguientes.)
*/

(async () => {
  const usuario = await Sesion.proteger(["ADMIN"], "index.html");
  if (!usuario) return;   // ya se está regresando al acceso

  document.getElementById("btn-cerrar-sesion").addEventListener("click", (evento) => {
    evento.preventDefault();
    Sesion.salir();
  });
})();
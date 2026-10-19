/*
  dashboard.js - Panel del administrador (dashboard.html)
  --------------------------------------------------------
  1. Protege la página: sin sesión de ADMIN regresa al login.
  2. Hace funcionar el botón "Cerrar Sesión".
  (Los datos reales del panel se conectarán en pasos siguientes.)
*/

(async () => {
  const usuario = await Sesion.proteger(["ADMIN"]);
  if (!usuario) return;   // ya se está regresando al login

  document.getElementById("btn-cerrar-sesion").addEventListener("click", (evento) => {
    evento.preventDefault();
    Sesion.salir();
  });
})();
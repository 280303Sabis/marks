/*
  sesion.js - Manejo de la sesión del portal web de MARK'S
  ---------------------------------------------------------
  Guarda el token y los datos del usuario al iniciar sesión.
  Se usa sessionStorage: la sesión se borra sola al cerrar el navegador.

  Uso en una página protegida (por ejemplo, dashboard.html):
    const usuario = await Sesion.proteger(["ADMIN"]);
*/

const Sesion = {
  _TOKEN: "marks_token",
  _USUARIO: "marks_usuario",

  // Guarda la sesión después de un login correcto.
  guardar(token, usuario) {
    sessionStorage.setItem(this._TOKEN, token);
    sessionStorage.setItem(this._USUARIO, JSON.stringify(usuario));
  },

  // Regresa el token, o null si no hay sesión.
  token() {
    return sessionStorage.getItem(this._TOKEN);
  },

  // Regresa los datos del usuario ({id, nombre, correo, rol, puntos}) o null.
  usuario() {
    try {
      return JSON.parse(sessionStorage.getItem(this._USUARIO));
    } catch (e) {
      return null;
    }
  },

  // Borra la sesión.
  cerrar() {
    sessionStorage.removeItem(this._TOKEN);
    sessionStorage.removeItem(this._USUARIO);
  },

  // Cierra la sesión y regresa al login.
  salir() {
    this.cerrar();
    location.replace("index.html");
  },

  // Protege una página: si no hay sesión o el rol no tiene permiso, regresa al login.
  // Si todo está bien, regresa los datos actualizados del usuario.
  async proteger(rolesPermitidos = ["ADMIN"]) {
    // Ocultar la página mientras se revisa, para que no se alcance a ver nada.
    document.documentElement.style.visibility = "hidden";

    const u = this.usuario();
    if (!this.token() || !u || !rolesPermitidos.includes(u.rol)) {
      this.salir();
      return null;
    }

    try {
      // Confirmar con la API que el token sigue siendo válido.
      const yo = await api("/auth/yo");
      if (!rolesPermitidos.includes(yo.rol)) {
        this.salir();
        return null;
      }
      document.documentElement.style.visibility = "visible";
      return yo;
    } catch (e) {
      if (e.estado === 0) {
        // La API está apagada: se muestra la página con un aviso en lugar de sacar al usuario.
        document.documentElement.style.visibility = "visible";
        alert(e.message);
        return u;
      }
      this.salir();   // cualquier otro error de sesión: regresar al login
      return null;
    }
  },
};
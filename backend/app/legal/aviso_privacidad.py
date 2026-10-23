"""
Aviso de Privacidad de MARK'S.

Cada vez que cambie el contenido, sube la VERSION aquí. config.py la lee de este
archivo, así se sabe qué versión aceptó cada usuario al registrarse.

Historial:
  1.1  2026-10-10  Primera versión publicada.
  1.2  2026-10-22  Pagos (solo marca y últimos 4 de la tarjeta), puntos,
                   opiniones y fotos públicas, y qué se borra al eliminar la cuenta.
"""
VERSION = "1.2"
FECHA = "2026-10-22"
CORREO_CONTACTO = "sabi.isaog@gmail.com"

SECCIONES = [
    {
        "titulo": "1. Responsable de tus datos",
        "texto": ("MARK'S es un proyecto integrador de estudiantes de la Universidad Tecnológica "
                  "Santa Catarina, Nuevo León, México. El equipo de MARK'S es responsable del uso y "
                  "protección de tus datos personales, conforme a la Ley Federal de Protección de "
                  "Datos Personales en Posesión de los Particulares."),
    },
    {
        "titulo": "2. Datos que recabamos",
        "texto": ("Datos de identificación y contacto: nombre, apellidos, fecha de nacimiento, "
                  "sexo (puedes elegir \"Prefiero no decirlo\"), correo electrónico y "
                  "teléfono (opcional). Datos de uso: sucursal elegida, productos escaneados, "
                  "compras y puntos de lealtad. Contenido que tú publicas: calificaciones "
                  "(estrellas), comentarios y hasta 3 fotos por opinión. Datos de seguridad: "
                  "fecha y hora de inicios de sesión y dirección IP. No recabamos datos "
                  "personales sensibles. De tu tarjeta solo guardamos la marca (por ejemplo, "
                  "VISA) y los últimos 4 dígitos para mostrarlos en tu ticket; el número "
                  "completo, la fecha de vencimiento y el código de seguridad nunca se guardan "
                  "en MARK'S."),
    },
    {
        "titulo": "3. Para qué usamos tus datos",
        "texto": ("Finalidades necesarias: crear y proteger tu cuenta, comprobar que eres mayor "
                  "de edad (18 años o más), procesar tus compras, generar tu ticket digital y tu "
                  "código QR de salida, administrar tus puntos de lealtad y publicar las "
                  "opiniones que tú decidas escribir. Finalidades adicionales: enviarte avisos "
                  "sobre promociones de productores locales de Nuevo León y promociones de "
                  "cumpleaños, y elaborar estadísticas generales sin identificarte (por ejemplo, "
                  "por rango de edad o sexo). Puedes negarte a las finalidades adicionales sin "
                  "que esto afecte el servicio."),
    },
    {
        "titulo": "4. Opiniones y fotos",
        "texto": ("Solo puedes opinar sobre productos que compraste, y escribir una opinión es "
                  "opcional. Tu opinión es pública: cualquier cliente de MARK'S la puede ver con "
                  "tu nombre y la inicial de tu apellido (por ejemplo, \"Ana L.\"); nunca se "
                  "muestran tu correo, teléfono ni apellidos completos. Las fotos se revisan y se "
                  "reducen de tamaño, y antes de publicarlas les quitamos los datos ocultos que "
                  "guarda el celular, como la ubicación (GPS), la fecha y el modelo de la cámara. "
                  "Te pedimos no subir fotos donde aparezcan personas, documentos o datos de "
                  "terceros. Un administrador puede ocultar una opinión que no cumpla las reglas, "
                  "y los clientes pueden reportarla. Puedes editar o borrar tu opinión y sus "
                  "fotos en cualquier momento desde \"Mis opiniones\"; al borrarla, las fotos se "
                  "eliminan de nuestros servidores."),
    },
    {
        "titulo": "5. Con quién compartimos tus datos",
        "texto": ("No vendemos ni rentamos tus datos. Solo se comparten con el procesador de pagos "
                  "para completar una compra, o cuando una autoridad competente lo solicite "
                  "conforme a la ley. Tus opiniones son públicas dentro de MARK'S, como se "
                  "explica en la sección 4."),
    },
    {
        "titulo": "6. Cómo protegemos tus datos",
        "texto": ("Tu contraseña se guarda cifrada y nadie del equipo puede verla. Tu cuenta se "
                  "bloquea temporalmente después de 3 intentos fallidos. Los códigos de "
                  "verificación caducan en 15 minutos y sirven una sola vez. El código QR de "
                  "salida va firmado para que no se pueda falsificar. Registramos los accesos "
                  "para detectar usos indebidos."),
    },
    {
        "titulo": "7. Tus derechos ARCO",
        "texto": ("Tienes derecho a Acceder a tus datos, Rectificarlos si son incorrectos, "
                  "Cancelarlos (eliminar tu cuenta) y Oponerte a su uso para finalidades "
                  "adicionales. Desde Mi cuenta puedes descargar una copia de tus datos "
                  "(perfil, compras, puntos y opiniones) y eliminar tu cuenta. También puedes "
                  "escribirnos a " + CORREO_CONTACTO + "."),
    },
    {
        "titulo": "8. Eliminación de tu cuenta",
        "texto": ("Al eliminar tu cuenta borramos tu nombre, correo, teléfono, fecha de "
                  "nacimiento, sexo y puntos, y también todas tus opiniones con sus fotos. "
                  "Los registros de compras se conservan sin datos que te identifiquen, solo para "
                  "fines contables y estadísticos."),
    },
    {
        "titulo": "9. Uso de tecnologías",
        "texto": ("La app guarda en tu celular un token de sesión para que no tengas que iniciar "
                  "sesión cada vez. El token caduca en 12 horas y se invalida si cambias tu "
                  "contraseña o cierras sesión en todos tus dispositivos. La app usa la cámara "
                  "para escanear productos y, solo si tú lo eliges, para tomar fotos de tus "
                  "opiniones; también puede abrir tu galería cuando eliges una foto. MARK'S "
                  "no accede a tus fotos sin que tú las selecciones."),
    },
    {
        "titulo": "10. Cambios a este aviso",
        "texto": ("Si este aviso cambia, te lo mostraremos en la app y te pediremos aceptarlo de "
                  "nuevo. Versión vigente: " + VERSION + ", publicada el " + FECHA + "."),
    },
]


def como_diccionario():
    return {"version": VERSION, "fecha": FECHA, "contacto": CORREO_CONTACTO, "secciones": SECCIONES}
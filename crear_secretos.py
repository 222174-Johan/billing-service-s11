
import json
from pathlib import Path
from secrets import token_hex

# Archivos privados que se generarán.
files = [
    Path(n)
    for n in (
        "billing.secrets.env",
        "cliente-propio.env",
        "cliente-par.env",
    )
]

# No sobrescribir tokens existentes.
if any(p.exists() for p in files):
    raise SystemExit(
        "Ya existen archivos privados: "
        "no se sobrescribieron ni rotaron los tokens."
    )

# Crear tokens distintos para las dos tiendas.
clients = {
    "tienda-a": token_hex(32),
    "tienda-b": token_hex(32),
}

# Configuración privada para Supabase.
files[0].write_text(
    "BILLING_CLIENTS='"
    + json.dumps(clients, separators=(",", ":"))
    + "'\n",
    encoding="utf-8",
)

# Token del aplicativo propio y del compañero.
for file, issuer in zip(files[1:], clients):
    file.write_text(
        "BILLING_TOKEN="
        + clients[issuer]
        + "\n",
        encoding="utf-8",
    )

# Restringir permisos cuando el sistema lo permita.
for file in files:
    try:
        file.chmod(0o600)
    except OSError:
        pass

print(
    "Creados billing.secrets.env, "
    "cliente-propio.env y cliente-par.env. "
    "No subir a Git."
)

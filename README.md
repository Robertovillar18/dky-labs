# Docker compose
El comando estándar para ejecutar un archivo docker-compose.yml es:
```
docker compose up
```
Si querés ejecutarlo en segundo plano (modo detached), usá:
```
docker compose up -d
```
## Algunas variantes útiles:
Especificar archivo compose (si no se llama docker-compose.yml):
```
docker compose -f nombre-del-archivo.yml up -d
```
Reconstruir las imágenes antes de levantar los servicios:
```
docker compose up -d --build
```
Ver logs en tiempo real:
```
docker compose logs -f
```
Detener y eliminar los contenedores:
```
docker compose down
```
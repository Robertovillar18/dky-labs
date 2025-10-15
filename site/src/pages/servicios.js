import React from 'react';
import Layout from '@theme/Layout';

export default function Servicios() {
  return (
    <Layout title="Servicios" description="Paquetes listos para contratar">
      <main className="container margin-vert--lg">
        <h1>Servicios</h1>
        <p>Paquetes con precio fijo y entregables claros — listos para empezar.</p>

        <div className="row">
          <div className="col col--4">
            <div className="card shadow--tl">
              <div className="card__header"><h3>Sprint Metadatos & BI</h3></div>
              <div className="card__body">
                <ul>
                  <li>Inventario de datos y mapa de metadatos</li>
                  <li>3 KPIs críticos en dashboard</li>
                  <li>Backlog priorizado (impacto/esfuerzo)</li>
                  <li>Informe ejecutivo</li>
                </ul>
                <p><strong>Duración:</strong> 2 semanas</p>
                <p><strong>Precio:</strong> €1.900</p>
              </div>
            </div>
          </div>

          <div className="col col--4">
            <div className="card shadow--tl">
              <div className="card__header"><h3>RAG Kickstart</h3></div>
              <div className="card__body">
                <ul>
                  <li>Asistente IA con FAQs/políticas del cliente</li>
                  <li>Indexación y búsqueda semántica</li>
                  <li>Trazas y evaluación básica</li>
                  <li>Guía de operación</li>
                </ul>
                <p><strong>Duración:</strong> 2 semanas</p>
                <p><strong>Precio:</strong> €2.400</p>
              </div>
            </div>
          </div>

          <div className="col col--4">
            <div className="card shadow--tl">
              <div className="card__header"><h3>Clasificación & Sentimiento</h3></div>
              <div className="card__body">
                <ul>
                  <li>Modelo base (clases/sentimiento)</li>
                  <li>Pipeline reproducible</li>
                  <li>Informe de performance</li>
                  <li>Recomendaciones de mejora</li>
                </ul>
                <p><strong>Duración:</strong> 1 semana</p>
                <p><strong>Precio:</strong> €1.200</p>
              </div>
            </div>
          </div>
        </div>

        <div className="margin-top--lg">
          <a className="button button--primary button--lg" href="/contacto">
            Quiero empezar
          </a>
        </div>
      </main>
    </Layout>
  );
}

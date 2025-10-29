import React from 'react';
import Layout from '@theme/Layout';

export default function SobreMi() {
  return (
    <Layout title="Sobre mí" description="Quién soy y cómo trabajo">
      <main className="container margin-vert--lg">
        <h1>Sobre mí</h1>
        <p>
          Soy Roberto Villar, consultor en datos e IA. He trabajado con organismos públicos (AGESIC)
          y empresas, enfocándome en metadatos, BI y asistentes IA con RAG. Me gusta entregar valor
          rápido con sprints y medir impacto.
        </p>
        <ul>
          <li>Gobierno del dato (DMBOK), OpenMetadata</li>
          <li>Dashboards operativos y KPIs</li>
          <li>RAG: búsqueda semántica + trazas + evaluación</li>
        </ul>
        <p>
          ¿Hablamos 20 minutos? <a href="/contacto">Agendá acá</a>.
        </p>
      </main>
    </Layout>
  );
}

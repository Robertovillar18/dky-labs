import React from 'react';
import Layout from '@theme/Layout';

export default function Contacto() {
  return (
    <Layout title="Contacto" description="Agendá una llamada o escribime">
      <main className="container margin-vert--lg">
        <h1>Contacto</h1>
        <p>Agendá una llamada de 30 minutos o escribime directo.</p>

        {/* Calendly embed (reemplaza el href si tenés tu link) */}
        <p>
          <a
            className="button button--primary button--lg"
            href="https://calendly.com/robertovillar18/30min/"
            target="_blank" rel="noreferrer"
          >
            Agendar llamada
          </a>
        </p>

        <p>
          Email: <a href="mailto:robertovillar18@gmail.com">robertovillar18@gmail.com</a><br/>
          Dublin · Montevideo
        </p>
      </main>
    </Layout>
  );
}

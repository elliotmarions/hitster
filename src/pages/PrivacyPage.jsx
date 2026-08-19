import { Link } from 'react-router-dom'
import DiscoBall from '../components/DiscoBall.jsx'

/**
 * Integritet och villkor.
 *
 * Sidan beskriver vad appen FAKTISKT gör – den är skriven mot koden, inte mot
 * en mall. Ändras något i vad som lagras eller vilka tredjeparter som blandas
 * in ska den här sidan ändras i samma commit.
 *
 * Det som ännu saknas för att vara komplett enligt GDPR är en kontaktväg till
 * personuppgiftsansvarig. Den är medvetet utelämnad tills det finns en adress
 * att publicera.
 */

function Section({ title, neon, children }) {
  return (
    <section className="panel space-y-3 p-6">
      <h2 className="neon-text font-display text-xl" style={{ '--neon': neon }}>
        {title}
      </h2>
      {children}
    </section>
  )
}

function Rad({ vad, varfor }) {
  return (
    <li className="flex flex-col gap-0.5 border-t border-white/10 py-2.5 first:border-t-0 first:pt-0 sm:flex-row sm:gap-4">
      <span className="font-display text-sm text-cream sm:w-52 sm:shrink-0">{vad}</span>
      <span className="text-sm text-muted">{varfor}</span>
    </li>
  )
}

export default function PrivacyPage() {
  return (
    <div className="mx-auto max-w-2xl space-y-8">
      <header className="text-center">
        <DiscoBall size={64} className="anim-float mx-auto" />
        <h1 className="wordmark mt-2 text-4xl">Integritet</h1>
        <p className="mt-3 text-sm text-muted">
          Vad Låtsnurran sparar om dig, varför, och hur du blir av med det. Skrivet på
          vanlig svenska.
        </p>
      </header>

      <Section title="Du kan spela utan att lämna något" neon="#b6ff3c">
        <p className="text-sm text-muted">
          Det krävs inget konto för att spela. Går du med i ett rum som gäst skapas ett
          anonymt id åt dig som lever i din webbläsare – det är kopplat till dina rum och
          brickor, men inte till din e-post, ditt namn eller din enhet i övrigt.
        </p>
        <p className="text-sm text-muted">
          Ett konto behövs bara om du vill att statistiken ska följa med mellan enheter.
        </p>
      </Section>

      <Section title="Det här sparas" neon="#22e6e6">
        <ul>
          <Rad
            vad="Visningsnamnet"
            varfor="Namnet du skriver in syns för alla i rummet. Har du konto kan du spara ett namn som följer med."
          />
          <Rad
            vad="E-postadressen"
            varfor="Bara om du skapar ett konto. Används för att logga in och för att återställa lösenord – aldrig för utskick."
          />
          <Rad
            vad="Matchstatistik"
            varfor="Antal spelade, vunna och oavgjorda matcher. Kopplas till kontot om du har ett, annars till gäst-id:t."
          />
          <Rad
            vad="Spelet självt"
            varfor="Rum, brickor, svar, ronder och lagchatt. Allt hör till ett rum och är till för att spelet ska fungera."
          />
          <Rad
            vad="I din webbläsare"
            varfor="Senaste visningsnamnet, din volymnivå, och din inloggning. Inget av det skickas vidare någonstans."
          />
        </ul>
      </Section>

      <Section title="Ingen spårning, inga annonser" neon="#ff2e9a">
        <p className="text-sm text-muted">
          Det finns inga annonser, ingen försäljning av uppgifter och inga
          analysverktyg i appen. Ingen tredjepartskod följer dig mellan sidor.
        </p>
      </Section>

      <Section title="Andra som är inblandade" neon="#b14dff">
        <ul>
          <Rad
            vad="Supabase"
            varfor="Databasen och inloggningen. Det är här kontot och spelen faktiskt ligger."
          />
          <Rad
            vad="Vercel"
            varfor="Sajten körs härifrån, och som alla webbservrar ser den vilka adresser som hämtas."
          />
          <Rad
            vad="Apple"
            varfor="Musikklippen är Apples officiella förhandslyssningar och hämtas direkt av din webbläsare från deras servrar. De ser alltså att någon hämtar ett klipp, men inte vem du är i spelet."
          />
          <Rad
            vad="Google Fonts"
            varfor="Typsnitten hämtas därifrån när sidan laddas."
          />
        </ul>
      </Section>

      <Section title="Vad andra spelare ser" neon="#ffc93c">
        <p className="text-sm text-muted">
          De som är i samma rum ser ditt visningsnamn, din bricka, dina svar och det du
          skriver i lagchatten. De ser inte din e-postadress. Välj ett namn du är bekväm
          med att visa – det behöver inte vara ditt riktiga.
        </p>
      </Section>

      <Section title="Bli av med det" neon="#33a6ff">
        <p className="text-sm text-muted">
          Har du konto kan du radera det själv under{' '}
          <Link to="/profil" className="text-cyan hover:underline">
            Min profil
          </Link>
          . Då försvinner kontot, statistiken, rummen du varit värd för och dina svar –
          på riktigt, inte dolt.
        </p>
        <p className="text-sm text-muted">
          Spelar du som gäst finns ingenting som pekar på dig som person. Rensar du
          webbläsarens data för sajten är kopplingen till gäst-id:t borta för din del.
        </p>
      </Section>

      <Section title="Villkor, kort" neon="#b6ff3c">
        <ul className="space-y-2">
          {[
            'Spelet är gratis och erbjuds i befintligt skick. Det kan sluta fungera, byta utseende eller försvinna.',
            'Rummet styrs av värden, som kan starta om, rätta domar och avsluta spelet.',
            'Lagchatten går till dina medspelare. Skriv inte sådant du inte vill att de läser.',
            'Musikklippen kommer från Apples publika förhandslyssningar och ägs av sina rättighetshavare.',
          ].map((t) => (
            <li key={t} className="flex gap-2 text-sm text-muted">
              <span aria-hidden className="text-lime">
                •
              </span>
              <span>{t}</span>
            </li>
          ))}
        </ul>
      </Section>

      <p className="text-center text-sm text-muted">
        <Link to="/" className="text-cyan hover:underline">
          ← Tillbaka till start
        </Link>
      </p>
    </div>
  )
}

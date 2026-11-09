import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext.jsx'
import DiscoBall from '../components/DiscoBall.jsx'
import NeonButton from '../components/ui/NeonButton.jsx'
import ConfirmDialog from '../components/ui/ConfirmDialog.jsx'

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
  const { deleteMyData } = useAuth()
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [deleteMsg, setDeleteMsg] = useState('')

  async function onDelete() {
    setDeleting(true)
    try {
      const hadData = await deleteMyData()
      setDeleteMsg(
        hadData
          ? 'Klart – allt som hörde till den här webbläsaren är raderat.'
          : 'Det fanns inget sparat att radera.',
      )
    } catch (e) {
      setDeleteMsg(e.message || 'Kunde inte radera just nu – försök igen.')
    } finally {
      setDeleting(false)
      setConfirmDelete(false)
    }
  }

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
          Det finns inga konton och ingen inloggning. När du skapar eller går med i ett
          rum får du ett anonymt id som lever i din webbläsare – det är kopplat till dina
          rum och brickor, men inte till någon e-post, ditt riktiga namn eller din enhet
          i övrigt.
        </p>
      </Section>

      <Section title="Det här sparas" neon="#22e6e6">
        <ul>
          <Rad
            vad="Visningsnamnet"
            varfor="Namnet du skriver in syns för alla i rummet."
          />
          <Rad
            vad="Matchräkning"
            varfor="Antal spelade, vunna och oavgjorda matcher räknas på det anonyma id:t. Den visas ingenstans."
          />
          <Rad
            vad="Spelet självt"
            varfor="Rum, brickor, svar, ronder och lagchatt. Allt hör till ett rum och är till för att spelet ska fungera."
          />
          <Rad
            vad="I din webbläsare"
            varfor="Senaste visningsnamnet, din volymnivå och ditt anonyma id. Inget av det skickas vidare någonstans."
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
            varfor="Databasen. Det är här rummen och spelen faktiskt ligger."
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
          skriver i lagchatten. Välj ett namn du är bekväm
          med att visa – det behöver inte vara ditt riktiga.
        </p>
      </Section>

      <Section title="Bli av med det" neon="#33a6ff">
        <p className="text-sm text-muted">
          Ingenting här pekar på dig som person. Vill du ändå bort med allt som hör till
          den här webbläsaren – rummen du varit värd för, dina svar, din matchräkning –
          raderas det på riktigt, inte dolt. Nästa gång du spelar får du ett nytt id.
        </p>
        <div className="flex flex-wrap items-center gap-3">
          <NeonButton variant="outline" neon="#ff2e9a" onClick={() => setConfirmDelete(true)}>
            Radera mina uppgifter
          </NeonButton>
          {deleteMsg && <span className="text-sm text-muted">{deleteMsg}</span>}
        </div>
        <ConfirmDialog
          open={confirmDelete}
          busy={deleting}
          title="Radera dina uppgifter?"
          message="Rum du är värd för stängs för alla, och dina svar och din matchräkning försvinner. Det går inte att ångra."
          confirmLabel="Radera allt"
          busyLabel="Raderar…"
          cancelLabel="Avbryt"
          onConfirm={onDelete}
          onCancel={() => setConfirmDelete(false)}
        />
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
        <Link to="/" className="inline-flex min-h-11 items-center text-cyan hover:underline">
          ← Tillbaka till start
        </Link>
      </p>
    </div>
  )
}

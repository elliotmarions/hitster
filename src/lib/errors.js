// Översätter fel från databasen till något en spelare kan förstå.
//
// Spellogiken ligger i RPC:er, så när något går fel är det ett Postgres-fel som
// bubblar upp genom PostgREST och landar rakt i spelvyns felruta. RPC:ernas
// EGNA `raise exception` (SQLSTATE P0001) är redan skrivna på svenska till
// spelaren ("Bara värden kan snurra") och släpps igenom orörda – det är allt
// annat som behöver en översättning, annars får värden se sådant här mitt i
// spelet:
//
//   new row for relation "rounds" violates check constraint
//   "rounds_category_check"
//
// Felen är fortfarande buggar som ska fixas i sak (det där var 0037) – men det
// hjälper ingen att läsa constraint-namn i en fest.

// Fel som betyder "servern vägrade av en anledning vi vill berätta rakt av".
const PASS_THROUGH = new Set([
  'P0001', // raise exception i våra egna RPC:er – meddelandet är redan på svenska
  'PT429', // rate limit (0027) – "För många anrop på kort tid …"
])

// Databas-jargong som aldrig ska visas för en spelare.
const RAW_DB_NOISE =
  /violates .*constraint|relation "|column "|schema cache|permission denied for|does not exist|invalid input syntax|deadlock detected|could not serialize/i

export function translateDbError(error) {
  const code = error?.code
  const msg = error?.message || ''

  if (PASS_THROUGH.has(code)) {
    return error instanceof Error ? error : new Error(msg)
  }

  // Tappad uppkoppling / offline – vanligast av allt på en telefon i en fest.
  if (error?.name === 'TypeError' || /fetch failed|network|load failed/i.test(msg)) {
    return new Error('Ingen kontakt med servern. Kolla nätet och försök igen.')
  }

  // Rättighetsfel: sessionen har hunnit ta slut, eller så är man inte längre
  // med i rummet (t.ex. utsparkad/rummet städat).
  if (code === '42501' || /jwt|not authenticated/i.test(msg)) {
    return new Error('Din session verkar ha gått ut. Ladda om sidan och gå med i rummet igen.')
  }

  // Allt annat som luktar Postgres/PostgREST: visa något begripligt i stället.
  // 23xxx = constraint-brott, 22xxx = datafel, PGRSTxxx = PostgREST själv.
  if (
    /^(23|22|40|42|53|55)/.test(code || '') ||
    /^PGRST/.test(code || '') ||
    RAW_DB_NOISE.test(msg)
  ) {
    return new Error('Något gick snett i spelet. Försök igen – funkar det inte, ladda om sidan.')
  }

  return error instanceof Error ? error : new Error(msg || 'Något gick fel.')
}

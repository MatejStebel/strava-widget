// Direct, read-only adapter for app.strava.cz. Protocol reference:
// https://github.com/kralicekgamer/strava.cz_api (revision 933e898).
// No meal names, course counts or table numbers are assumed.
function dateKey(value) {
    var text = String(value || "").trim()
    var match = /^(\d{4})-(\d{2})-(\d{2})(?:$|T| )/.exec(text)
    if (match) return match[1] + "-" + match[2] + "-" + match[3]
    match = /^(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})$/.exec(text)
    return match ? match[3] + "-" + match[2].padStart(2, "0") + "-" + match[1].padStart(2, "0") : ""
}

function localDate(date) {
    return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0")
        + "-" + String(date.getDate()).padStart(2, "0")
}

function dayOffset(date, offset) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + offset)
}

function parseMenu(data) {
    if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("Invalid menu")
    var tables = Object.keys(data).filter(function(key) { return /^table\d+$/.test(key) })
    if (!tables.length) throw new Error("Missing menu tables")
    tables.sort(function(a, b) { return Number(a.slice(5)) - Number(b.slice(5)) })
    var meals = []
    tables.forEach(function(key) {
        if (!Array.isArray(data[key])) throw new Error("Invalid menu table")
        data[key].forEach(function(row) {
            if (!row || typeof row !== "object") throw new Error("Invalid meal")
            // Auxiliary rows have no meal name. A malformed meal must not look like an empty day.
            if (row.nazev === undefined && row.popis === undefined) return
            var date = dateKey(row.datum)
            if (!date) throw new Error("Invalid meal date")
            var count = Number(String(row.pocet === undefined ? "" : row.pocet).replace(",", "."))
            var known = row.pocet !== undefined && row.pocet !== null && String(row.pocet).trim() !== "" && isFinite(count)
            meals.push({date: date, name: String(row.nazev || row.popis || ""),
                description: String(row.delsiPopis || (row.nazev ? row.popis || "" : "")),
                course: String(row.druh_popis || row.druh_chod || row.druh || ""),
                allergens: String(row.alergeny_text || ""), price: String(row.cena || ""),
                ordered: known && count > 0, orderKnown: known, count: known ? count : 0})
        })
    })
    return meals
}

function mealsForDay(meals, day, showUnordered) {
    return meals.filter(function(meal) { return meal.date === day && (showUnordered || meal.ordered) })
}

function errorCode(data) {
    return data && data.state === "error" ? String(data.number || "unknown") : ""
}

function loginBody(cafeteria, username, password) {
    return {cislo: cafeteria, jmeno: username, heslo: password,
        zustatPrihlasen: false, environment: "W", lang: "CZ"}
}

function menuBody(cafeteria, sid, s5url) {
    return {cislo: cafeteria, sid: sid, s5url: s5url, lang: "CZ",
        konto: 0, podminka: "", ignoreCert: "false"}
}

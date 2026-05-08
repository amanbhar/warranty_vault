export function monthsToYearsAndMonths(months) {
  if (!months || months <= 0) {
    return { years: 0, months: 0, display: 'N/A', totalMonths: 0 };
  }

  const years = Math.floor(months / 12);
  const monthsOnly = months % 12;

  const parts = [];
  if (years > 0) parts.push(`${years} year${years > 1 ? 's' : ''}`);
  if (monthsOnly > 0) parts.push(`${monthsOnly} month${monthsOnly > 1 ? 's' : ''}`);

  return {
    years,
    months: monthsOnly,
    display: parts.join(', ') || 'N/A',
    totalMonths: months
  };
}

export function yearsAndMonthsToMonths(years, months) {
  const y = parseInt(years) || 0;
  const m = parseInt(months) || 0;
  return y * 12 + m;
}

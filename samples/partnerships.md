---
type: map
title: Partnerships
inverse:
  works_at: employs
  advises: advised_by
---

---
id: riverside-council
type: org
title: Riverside City Council
weight: lead
rel:
  employs: [dana-whitfield, marcus-obi]
---

The anchor relationship. Everything routes through [[dana-whitfield]].

---
id: harborlight
type: org
title: Harborlight Foundation
rel:
  advises: [riverside-council]
---

Grant-making partner. [[priya-raman]] runs the program side.

---
id: dana-whitfield
type: person
title: Dana Whitfield
rel:
  works_at: [riverside-council]
---

Director of partnerships. First call for anything council-side.

---
id: marcus-obi
type: person
title: Marcus Obi
rel:
  works_at: [riverside-council]
---

Data lead. Owns the open-data pipeline.

---
id: priya-raman
type: person
title: Priya Raman
rel:
  works_at: [harborlight]
  advises: [dana-whitfield]
---

Program officer at [[harborlight]]. Advises [[dana-whitfield]] on grants.

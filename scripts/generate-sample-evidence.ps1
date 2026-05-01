# ---------------------------------------------------------------------------
# generate-sample-evidence.ps1
#
# Regenerates the seed PDFs under
#   sample-app/api/src/main/resources/data/sample-evidence/
#
# These are intentionally hand-rolled, dependency-free PDF 1.4 documents
# (Helvetica + Helvetica-Bold built-in fonts only). They are NOT real
# evidence and contain only synthetic, fictional content for the workshop.
#
# Usage:
#   pwsh ./scripts/generate-sample-evidence.ps1
#
# Output: 5 multi-page PDFs (typically 5-15 KB each) overwritten in place.
# ---------------------------------------------------------------------------

[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path $PSScriptRoot '..\sample-app\api\src\main\resources\data\sample-evidence')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Page geometry (US Letter, 72 dpi).
$script:PageWidth      = 612
$script:PageHeight     = 792
$script:Margin         = 54        # 0.75"
$script:LineHeight     = 14
$script:LinesPerPage   = 48        # leaves room for header + footer
$script:MaxCharsPerLn  = 86        # rough fit for 11pt Helvetica at 504pt width

function Get-WrappedLines {
    param(
        [Parameter(Mandatory)] [string] $Text,
        [int] $MaxChars = $script:MaxCharsPerLn
    )
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($paragraph in ($Text -split "`n")) {
        $current = ''
        foreach ($word in ($paragraph -split '\s+' | Where-Object { $_.Length -gt 0 })) {
            if ($current.Length -eq 0) {
                $current = $word
            }
            elseif (($current.Length + 1 + $word.Length) -gt $MaxChars) {
                $out.Add($current) | Out-Null
                $current = $word
            }
            else {
                $current = "$current $word"
            }
        }
        $out.Add($current) | Out-Null
    }
    return ,$out.ToArray()
}

function ConvertTo-PdfString {
    param([string] $Text)
    if ($null -eq $Text) { return '' }
    # Order matters: backslash first.
    $t = $Text -replace '\\', '\\'
    $t = $t -replace '\(', '\('
    $t = $t -replace '\)', '\)'
    return $t
}

function Add-Ascii {
    param(
        [System.Collections.Generic.List[byte]] $Buffer,
        [string] $Text
    )
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Text)
    $Buffer.AddRange($bytes)
}

# Build a single page content stream from a list of "ops":
#   @{ Font='F1'|'F2'; Size=11; Text='...' }
function Build-PageStream {
    param(
        [Parameter(Mandatory)] [object[]] $Ops,
        [string] $HeaderText,
        [string] $FooterText
    )
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine('BT')
    # Header (small grey-ish, rendered as plain Helvetica-Bold 9pt at top).
    if ($HeaderText) {
        $null = $sb.AppendLine("/F2 9 Tf")
        $null = $sb.AppendLine("$($script:Margin) $($script:PageHeight - 30) Td")
        $null = $sb.AppendLine("(" + (ConvertTo-PdfString $HeaderText) + ") Tj")
        # Reset to body start position.
        $null = $sb.AppendLine("$(- $script:Margin) $(-(($script:PageHeight - 30) - ($script:PageHeight - $script:Margin))) Td")
    }
    else {
        $null = $sb.AppendLine("$($script:Margin) $($script:PageHeight - $script:Margin) Td")
    }

    $first = $true
    foreach ($op in $Ops) {
        if (-not $first) {
            $null = $sb.AppendLine("0 -$($script:LineHeight) Td")
        }
        $null = $sb.AppendLine("/$($op.Font) $($op.Size) Tf")
        $null = $sb.AppendLine("(" + (ConvertTo-PdfString $op.Text) + ") Tj")
        $first = $false
    }
    $null = $sb.AppendLine('ET')

    if ($FooterText) {
        $null = $sb.AppendLine('BT')
        $null = $sb.AppendLine("/F1 9 Tf")
        $null = $sb.AppendLine("$($script:Margin) 30 Td")
        $null = $sb.AppendLine("(" + (ConvertTo-PdfString $FooterText) + ") Tj")
        $null = $sb.AppendLine('ET')
    }
    return $sb.ToString()
}

function New-PdfDocument {
    param(
        [Parameter(Mandatory)] [string] $OutPath,
        [Parameter(Mandatory)] [string] $Title,
        [Parameter(Mandatory)] [string] $Classification,
        [Parameter(Mandatory)] [object[]] $Sections   # @( @{Heading='...'; Body='...'}, ... )
    )

    # ---- Compose a flat ordered list of "ops" for the whole document ----
    $allOps = New-Object System.Collections.Generic.List[object]

    $allOps.Add([pscustomobject]@{ Font='F2'; Size=18; Text=$Title }) | Out-Null
    $allOps.Add([pscustomobject]@{ Font='F1'; Size=11; Text=' ' })    | Out-Null
    $allOps.Add([pscustomobject]@{ Font='F2'; Size=11; Text="Classification: $Classification" }) | Out-Null
    $allOps.Add([pscustomobject]@{ Font='F1'; Size=11; Text=' ' })    | Out-Null

    foreach ($section in $Sections) {
        $allOps.Add([pscustomobject]@{ Font='F2'; Size=13; Text=$section.Heading }) | Out-Null
        $allOps.Add([pscustomobject]@{ Font='F1'; Size=11; Text=' ' })             | Out-Null
        foreach ($line in (Get-WrappedLines -Text $section.Body)) {
            $allOps.Add([pscustomobject]@{ Font='F1'; Size=11; Text=$line }) | Out-Null
        }
        $allOps.Add([pscustomobject]@{ Font='F1'; Size=11; Text=' ' }) | Out-Null
    }

    # ---- Group ops into pages ----
    $pages = New-Object System.Collections.Generic.List[object]
    $offset = 0
    while ($offset -lt $allOps.Count) {
        $end = [Math]::Min($offset + $script:LinesPerPage, $allOps.Count) - 1
        $slice = ,@($allOps[$offset..$end])
        $pages.Add($slice) | Out-Null
        $offset += $script:LinesPerPage
    }
    $numPages = $pages.Count

    # ---- Build per-page content streams ----
    $contentStreams = @()
    for ($p = 0; $p -lt $numPages; $p++) {
        $header = "$Title  -  $Classification"
        $footer = "Synthetic workshop sample - not real evidence    Page $($p + 1) of $numPages"
        $contentStreams += (Build-PageStream -Ops $pages[$p] -HeaderText $header -FooterText $footer)
    }

    # ---- Assemble PDF objects ----
    # Object numbering plan:
    #   1 Catalog
    #   2 Pages tree
    #   3..(2+numPages)  Page objects
    #   (3+numPages)     Font F1
    #   (4+numPages)     Font F2
    #   (5+numPages)..(4+2*numPages) Content streams
    $catalogObj = 1
    $pagesObj   = 2
    $pageObjs   = @(); for ($i = 0; $i -lt $numPages; $i++) { $pageObjs += (3 + $i) }
    $fontF1Obj  = 3 + $numPages
    $fontF2Obj  = 4 + $numPages
    $contentObjs = @(); for ($i = 0; $i -lt $numPages; $i++) { $contentObjs += (5 + $numPages + $i) }
    $totalObjs  = 4 + 2 * $numPages

    $objects = @{}
    $objects[$catalogObj] = "<</Type/Catalog/Pages $pagesObj 0 R>>"
    $kids = ($pageObjs | ForEach-Object { "$_ 0 R" }) -join ' '
    $objects[$pagesObj]   = "<</Type/Pages/Kids[$kids]/Count $numPages>>"
    for ($i = 0; $i -lt $numPages; $i++) {
        $objects[$pageObjs[$i]] = "<</Type/Page/MediaBox[0 0 $($script:PageWidth) $($script:PageHeight)]/Parent $pagesObj 0 R/Resources<</Font<</F1 $fontF1Obj 0 R/F2 $fontF2Obj 0 R>>>>/Contents $($contentObjs[$i]) 0 R>>"
    }
    $objects[$fontF1Obj] = "<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>"
    $objects[$fontF2Obj] = "<</Type/Font/Subtype/Type1/BaseFont/Helvetica-Bold>>"
    for ($i = 0; $i -lt $numPages; $i++) {
        $stream = $contentStreams[$i]
        $len = [System.Text.Encoding]::ASCII.GetByteCount($stream)
        $objects[$contentObjs[$i]] = "<</Length $len>>`nstream`n$stream`nendstream"
    }

    # ---- Serialize, recording byte offsets ----
    $buf = [System.Collections.Generic.List[byte]]::new()
    Add-Ascii $buf "%PDF-1.4`n"
    # Binary marker comment (4 high-bit bytes) so consumers don't treat as ASCII.
    $buf.Add(0x25) | Out-Null
    $buf.Add(0xE2) | Out-Null
    $buf.Add(0xE3) | Out-Null
    $buf.Add(0xCF) | Out-Null
    $buf.Add(0xD3) | Out-Null
    $buf.Add(0x0A) | Out-Null

    $offsets = @{}
    for ($n = 1; $n -le $totalObjs; $n++) {
        $offsets[$n] = $buf.Count
        Add-Ascii $buf "$n 0 obj`n"
        Add-Ascii $buf "$($objects[$n])`n"
        Add-Ascii $buf "endobj`n"
    }

    $xrefOffset = $buf.Count
    Add-Ascii $buf "xref`n"
    Add-Ascii $buf "0 $($totalObjs + 1)`n"
    Add-Ascii $buf "0000000000 65535 f`r`n"
    for ($n = 1; $n -le $totalObjs; $n++) {
        Add-Ascii $buf ('{0:D10} 00000 n' -f $offsets[$n])
        Add-Ascii $buf "`r`n"
    }
    Add-Ascii $buf "trailer`n"
    Add-Ascii $buf "<</Size $($totalObjs + 1)/Root $catalogObj 0 R>>`n"
    Add-Ascii $buf "startxref`n"
    Add-Ascii $buf "$xrefOffset`n"
    Add-Ascii $buf "%%EOF`n"

    [System.IO.File]::WriteAllBytes($OutPath, $buf.ToArray())
    return [pscustomobject]@{ Path = $OutPath; Pages = $numPages; Bytes = $buf.Count }
}

# ---------------------------------------------------------------------------
# Synthetic content for each evidence file. All names, dates, hashes,
# numbers, and narratives are fictional.
# ---------------------------------------------------------------------------

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$results = @()

# 1. witness-statement.pdf -------------------------------------------------
$results += New-PdfDocument `
    -OutPath (Join-Path $OutDir 'witness-statement.pdf') `
    -Title 'Witness Statement - CASE-2024-001' `
    -Classification 'Confidential' `
    -Sections @(
        @{
            Heading = 'Statement Header'
            Body    = @"
Case Reference: CASE-2024-001 (Operation Shield)
Statement Number: WS-2024-0017
Witness: Mitchell, Sarah J.
Date of Statement: 15 March 2024
Time of Statement: 10:30 (local)
Location: Central Precinct, Interview Room 3
Recording Officer: Det. Robert Chen, Badge 4471
Statement Type: Voluntary, written and signed

This statement is made by the witness named above of their own free will,
without coercion, and with the understanding that it may be used as
evidence in a criminal proceeding. The witness has been advised of their
right to consult counsel before providing this statement and has elected
to proceed without representation present.
"@
        },
        @{
            Heading = 'Witness Background'
            Body    = @"
The witness is a thirty-four year old systems administrator employed by
Halberd Logistics for the past six years. They reside in the city and
have no prior involvement with law enforcement beyond a 2019 traffic
citation that was paid in full. The witness holds a bachelor of science
degree in computer information systems and a current industry security
certification. Their employer has confirmed their employment status,
length of tenure, and access privileges to the systems referenced in
this statement.
"@
        },
        @{
            Heading = 'Account of Events'
            Body    = @"
On the morning of 12 March 2024, at approximately 07:42, the witness
arrived at their place of employment and began their normal duties. At
approximately 08:15 they received an automated alert from the company's
endpoint detection platform indicating anomalous outbound network
traffic from a workstation assigned to a colleague. The alert classified
the traffic as a potential data exfiltration event with a confidence
score of 0.81.

The witness states that they followed the documented incident response
procedure: they isolated the affected workstation from the network,
captured a memory image using the standard forensic tooling provided by
the security operations team, and notified their direct supervisor and
the on-call security analyst. At approximately 09:05 the affected user
arrived at the office and was advised that their workstation had been
quarantined pending investigation.

The witness further states that the affected user appeared agitated upon
learning of the quarantine action, and asked specifically whether the
captured image had been transferred off the local network. The witness
responded that all evidence handling had followed company policy and
declined to discuss specifics. The user then left the office and did
not return that day.
"@
        },
        @{
            Heading = 'Items Provided to Investigators'
            Body    = @"
1. A copy of the automated alert log covering the period 07:00 to 10:00
   on 12 March 2024, exported from the endpoint detection platform.
2. A copy of the company's incident response runbook (revision 4.2,
   effective 01 January 2024) used during the response.
3. A copy of the workstation provisioning record for the affected
   device, including its assigned asset tag and last-known software
   inventory.
4. The witness's contemporaneous handwritten notes from the response,
   totalling four pages, photographed and provided as a PDF.

All items were provided voluntarily and the witness understands that
copies will be retained by investigators and may be disclosed to other
parties as part of the proceeding.
"@
        },
        @{
            Heading = 'Declaration'
            Body    = @"
I, the undersigned witness, declare under penalty of perjury that the
foregoing statement is true and correct to the best of my knowledge and
recollection. I have read this statement in full, I have had the
opportunity to make corrections, and I affirm that it accurately
represents the events as I observed them.

Signed: ____________________________
Witness: Sarah J. Mitchell
Date:    15 March 2024

Witnessed by: ____________________________
Officer: Det. Robert Chen, Badge 4471
Date:    15 March 2024
"@
        }
    )

# 2. forensic-report.pdf ---------------------------------------------------
$results += New-PdfDocument `
    -OutPath (Join-Path $OutDir 'forensic-report.pdf') `
    -Title 'Digital Forensic Examination Report - CASE-2024-001' `
    -Classification 'Restricted' `
    -Sections @(
        @{
            Heading = 'Examination Header'
            Body    = @"
Case Reference: CASE-2024-001 (Operation Shield)
Report Number: FR-2024-0042
Examiner: A. Patel, Certified Digital Forensic Examiner #DFE-7711
Examination Period: 17 - 22 March 2024
Reporting Date: 22 March 2024
Laboratory: Regional Digital Evidence Lab, Bay 4
Equipment Used: Write blocker model WB-3 (s/n 4471a),
                imaging workstation FW-12 (s/n 88203),
                analysis workstation AW-5 (s/n 91144).
"@
        },
        @{
            Heading = 'Items Examined'
            Body    = @"
Item 1: Workstation hard drive removed from asset HL-WK-2188.
        Manufacturer SeaCorp, model SC500, serial number SC50012077X.
        Condition on receipt: intact, no visible damage, factory seal
        on chassis broken (consistent with normal in-service use).

Item 2: Memory image captured from the same workstation prior to
        shutdown by the on-site responder. File name
        HL-WK-2188-2024-03-12-0815.mem, size 17,179,869,184 bytes.

Item 3: A USB mass storage device recovered from the user's desk
        drawer. Manufacturer Briskcore, model BC-32, serial number
        BC32-09144. Capacity reported as 32 GiB.
"@
        },
        @{
            Heading = 'Acquisition and Verification'
            Body    = @"
Each item was acquired using a hardware write blocker into a forensic
container in the EnCase Evidence File format (E01). After acquisition,
the source media was returned to the evidence locker and the working
copy was verified against the source by recomputing both MD5 and SHA-256
hashes of the raw block stream. All three items verified successfully
on the first attempt.

Item 1 hash values:
  MD5    : 0a8e3f12cc91d3a4b5e6f7081a9c2b34
  SHA-256: 7a9c1b3d5e7f91123456789abcdef0fedcba9876543210abcdef9876543210ab

Item 2 hash values:
  MD5    : 1b9f4e23dd02a4b5c6d7e8092b0d3c45
  SHA-256: 8b0d2c4e6f80a1234567890bcdef0123456789abcdef0123456789abcdef0123

Item 3 hash values:
  MD5    : 2c0a5f34ee13b5c6d7e8f9103c1e4d56
  SHA-256: 9c1e3d5f7a91b234567890cdef0123456789abcdef0123456789abcdef012345
"@
        },
        @{
            Heading = 'Findings'
            Body    = @"
Examination of Item 1 recovered the user's profile, browser history,
shell command history, and a directory of compressed archives in the
path Users/jdoe/Documents/projects/intl/. The archives, totalling
4.7 GiB, were password protected. Examination of Item 2 recovered the
plaintext password from a process memory region associated with the
archive utility. The same password successfully decrypted all archives.

The decrypted archives contained a mixture of presentation slides,
spreadsheets containing tabular price data, and source code from a
private repository. Metadata on the spreadsheets indicated authorship
by individuals not employed by the company. File-system timestamps
suggested the archives were created in the 72 hours immediately prior
to the alert.

Examination of Item 3 recovered seventeen of the eighteen archives
recovered from Item 1 in identical form. The eighteenth was present
but truncated at 1.2 MiB out of an expected 412 MiB, consistent with
an interrupted write operation.
"@
        },
        @{
            Heading = 'Conclusions'
            Body    = @"
The artefacts examined are consistent with the staging and partial
exfiltration of approximately 4.7 GiB of compressed material via the
USB mass storage device identified as Item 3. The plaintext password
recovered from Item 2 ties the archive creation activity to a process
running under the user's interactive session at a time when the
authenticated user was logged in. No evidence of remote intrusion,
malware execution, or third-party tampering was identified during the
examination.

This report is offered to a reasonable degree of professional certainty
and represents the examiner's findings based on the items submitted and
the methods described above. The examiner is available to provide
testimony regarding the methodology and findings if required.
"@
        }
    )

# 3. surveillance-log.pdf -------------------------------------------------
$results += New-PdfDocument `
    -OutPath (Join-Path $OutDir 'surveillance-log.pdf') `
    -Title 'Surveillance Activity Log - CASE-2024-002' `
    -Classification 'Internal' `
    -Sections @(
        @{
            Heading = 'Operation Summary'
            Body    = @"
Case Reference: CASE-2024-002
Operation: Static surveillance of subject vehicle and residence in
           connection with suspected fraudulent transaction activity.
Lead Officer: Analyst James Porter, Badge 5512
Surveillance Period: 28 March - 02 April 2024
Posts: Two-vehicle rotating coverage from 06:00 to 22:00 daily, with
       a fixed camera deployment covering the residence frontage on a
       continuous basis. All entries below are taken from contemporaneous
       officer notes and corroborated against camera timestamps.
"@
        },
        @{
            Heading = 'Day 1 - 28 March 2024'
            Body    = @"
06:02 - Post 1 (vehicle Bravo) on station, line of sight to driveway.
06:14 - Subject vehicle (silver sedan, plate ABC-123) observed on
        driveway, no movement, lights off.
07:48 - Subject male (described as 1.8m, dark jacket, baseball cap)
        exits residence, enters subject vehicle, departs eastbound.
07:52 - Post 1 follows at distance, hands off to Post 2 at intersection
        of Maple and 4th.
08:23 - Subject vehicle parks at 1422 Industrial Way (warehouse, no
        signage). Subject male enters via side door.
10:11 - Subject male exits warehouse carrying a soft-sided black bag
        (approx. 60cm long). Returns to vehicle, departs westbound.
11:45 - Subject vehicle returns to residence. Male exits with bag,
        enters residence. No further movement observed before shift end.
21:58 - Coverage stood down, no further activity logged for the day.
"@
        },
        @{
            Heading = 'Day 2 - 29 March 2024'
            Body    = @"
06:00 - Coverage resumed.
09:14 - Female (described as 1.65m, light jacket) arrives at residence
        in a separate vehicle (red hatchback, plate XYZ-789), enters
        without knocking.
10:42 - Both subjects exit residence, enter the silver sedan, depart
        northbound. Post 2 follows.
11:30 - Subjects observed at municipal post office, female enters, male
        remains in vehicle. Female exits at 11:48 carrying a small
        padded envelope.
12:35 - Subjects return to residence.
14:10 - Female departs alone in red hatchback, southbound. Hand-off
        broken at city limits.
20:33 - Lights observed at residence consistent with continued
        occupancy. No further movement.
"@
        },
        @{
            Heading = 'Days 3 to 5 - 30 March to 02 April 2024'
            Body    = @"
Coverage continued on the same schedule. The pattern of brief warehouse
visits in the morning followed by a return to the residence repeated
daily. On 31 March a third party (male, late twenties, riding a black
motorcycle) made a brief visit to the warehouse around 13:20 and
departed within ten minutes. On 01 April the subject vehicle did not
leave the residence; static observation confirmed continuous
occupancy by the primary subject.

On 02 April at 08:42 the subject vehicle departed for the warehouse on
the established pattern. The vehicle was not observed to return by the
end of the surveillance period at 22:00. Coverage was stood down at
22:00 in accordance with the operation order. A summary disposition
report follows separately.
"@
        }
    )

# 4. chain-of-custody.pdf -------------------------------------------------
$results += New-PdfDocument `
    -OutPath (Join-Path $OutDir 'chain-of-custody.pdf') `
    -Title 'Chain of Custody Record - CASE-2024-003' `
    -Classification 'Confidential' `
    -Sections @(
        @{
            Heading = 'Item Identification'
            Body    = @"
Case Reference: CASE-2024-003 (Surveillance Video Authentication)
Evidence Tag: ET-2024-1188
Description: One (1) optical disc, DVD-R, in protective sleeve.
             Handwritten label reads "Lobby Cam 02 - 12-03-24 - cut".
Recovered: 13 March 2024 at 14:15 from administrative office of
           Halberd Logistics, 1422 Industrial Way.
Recovering Officer: Det. Robert Chen, Badge 4471

Initial inspection: disc appears intact, no visible scratches or
                     damage to recording surface. Label is original
                     handwriting; ink consistent with single-author
                     application.
"@
        },
        @{
            Heading = 'Custody Transfers'
            Body    = @"
Transfer 1
  From: Det. Robert Chen, Badge 4471 (recovering officer)
  To:   Sgt. David Park, Badge 3320 (evidence locker custodian)
  Date and time: 13 March 2024, 18:42
  Location: Central Precinct, Evidence Locker 3
  Reason: Initial intake and storage pending forensic examination.
  Signature on file: yes (locker logbook page 117, line 8).

Transfer 2
  From: Sgt. David Park, Badge 3320
  To:   Tech. Officer Lisa Chen, Badge 6604 (forensic technician)
  Date and time: 17 March 2024, 09:10
  Location: Regional Digital Evidence Lab, Reception
  Reason: Forensic imaging and authentication examination.
  Signature on file: yes (lab intake form FE-2024-0119).

Transfer 3
  From: Tech. Officer Lisa Chen, Badge 6604
  To:   Sgt. David Park, Badge 3320
  Date and time: 22 March 2024, 16:25
  Location: Central Precinct, Evidence Locker 3
  Reason: Examination complete; disc returned to long-term storage.
  Signature on file: yes (locker logbook page 121, line 14).
"@
        },
        @{
            Heading = 'Working Copies and Derivatives'
            Body    = @"
During the period of Transfer 2 the forensic technician created two
forensic copies of the disc for examination purposes:

Working Copy A: ISO image, file name LobbyCam02-2024-03-12-cut.iso,
                size 4,294,950,912 bytes,
                SHA-256 11aa22bb33cc44dd55ee66ff77001122334455667788
                       99aabbccddeeff00112233445566778899aabbccddee.
                Stored on lab evidence server, retention indefinite.

Working Copy B: H.264 transcode of the recovered video stream for
                in-court playback, file name
                LobbyCam02-2024-03-12-cut-playback.mp4,
                size 614,492,160 bytes,
                SHA-256 22bb33cc44dd55ee66ff7700112233445566778899aa
                       bbccddeeff00112233445566778899aabbccddeeff00.
                Stored on lab evidence server, retention indefinite.

Both working copies were created on the lab examination workstation
AW-5 (s/n 91144) using a hardware optical drive in read-only mode.
Hash values were recorded immediately after creation and verified
against a recomputed value at the close of the examination period.
Both copies verified successfully.
"@
        },
        @{
            Heading = 'Acknowledgement'
            Body    = @"
The undersigned custodians acknowledge that the chain of custody
recorded above is complete, accurate, and consistent with the
evidence locker logbook and the laboratory intake records. No gaps,
unrecorded transfers, or unaccounted-for periods exist between the
recovery of the original disc and its current storage in Evidence
Locker 3.

Sgt. David Park, Badge 3320 (Evidence Custodian)
Signature: ____________________________  Date: ____________________

Tech. Officer Lisa Chen, Badge 6604 (Examiner)
Signature: ____________________________  Date: ____________________
"@
        }
    )

# 5. contract-agreement.pdf -----------------------------------------------
$results += New-PdfDocument `
    -OutPath (Join-Path $OutDir 'contract-agreement.pdf') `
    -Title 'Master Services Agreement - Disputed - CASE-2024-005' `
    -Classification 'Internal' `
    -Sections @(
        @{
            Heading = 'Parties and Effective Date'
            Body    = @"
This Master Services Agreement ("Agreement") is entered into as of the
First (1st) day of February, Two Thousand and Twenty-Four ("Effective
Date"), by and between:

  Halberd Logistics, a corporation organised under the laws of the
  jurisdiction in which it maintains its principal place of business
  at 1422 Industrial Way, hereafter referred to as "Client"; and

  Cobalt Integrations LLC, a limited liability company organised under
  the laws of the jurisdiction in which it maintains its principal
  place of business at 88 Civic Plaza, Suite 410, hereafter referred
  to as "Provider".

The Client and Provider may be referred to individually as a "Party"
and collectively as the "Parties".
"@
        },
        @{
            Heading = '1. Scope of Services'
            Body    = @"
The Provider shall furnish the services described in any Statement of
Work executed by both Parties under this Agreement (each, an "SOW"),
including but not limited to systems integration, custom software
development, deployment automation, and post-production support
during the warranty period defined in the relevant SOW. The Provider
shall perform the services in a workmanlike manner consistent with
generally accepted industry practice for engagements of similar scope
and complexity.

No services other than those described in an executed SOW shall be
deemed to be within the scope of this Agreement, and the Provider
shall not be entitled to compensation for work performed outside the
scope of an executed SOW absent prior written authorisation by an
authorised representative of the Client.
"@
        },
        @{
            Heading = '2. Compensation and Payment'
            Body    = @"
The Client shall pay the Provider the fees set forth in each SOW.
Unless an SOW expressly provides otherwise, the Provider shall invoice
the Client monthly for services performed during the preceding calendar
month. Each invoice shall identify the SOW under which the services
were performed and shall include sufficient detail to permit the
Client to verify the work performed.

Invoices shall be due and payable thirty (30) days after the date of
invoice. Amounts not paid within sixty (60) days of the invoice date
shall accrue interest at the lesser of one percent (1%) per month or
the maximum rate permitted by applicable law, computed daily until
paid in full.
"@
        },
        @{
            Heading = '3. Confidentiality'
            Body    = @"
Each Party acknowledges that in the performance of this Agreement it
may receive or have access to information of the other Party that is
non-public, confidential, or proprietary in nature ("Confidential
Information"). Each Party agrees to use Confidential Information of
the other Party solely for the purpose of performing its obligations
under this Agreement and to protect such Confidential Information
using the same degree of care that it uses to protect its own
information of like sensitivity, but in no event less than a
reasonable degree of care.

The obligations set forth in this Section shall survive the
termination of this Agreement for a period of five (5) years.
"@
        },
        @{
            Heading = '4. Term and Termination'
            Body    = @"
This Agreement shall commence on the Effective Date and shall continue
in effect until terminated as provided herein. Either Party may
terminate this Agreement for convenience upon ninety (90) days prior
written notice to the other Party, provided that any SOW then in
effect shall continue in accordance with its terms unless separately
terminated.

Either Party may terminate this Agreement immediately upon written
notice in the event that the other Party (a) materially breaches this
Agreement and fails to cure such breach within thirty (30) days after
receipt of written notice describing the breach in reasonable detail,
or (b) becomes insolvent, files a petition in bankruptcy, or has such
a petition filed against it that is not dismissed within sixty (60)
days.
"@
        },
        @{
            Heading = '5. Signatures'
            Body    = @"
IN WITNESS WHEREOF, the Parties hereto have caused this Agreement to
be executed by their duly authorised representatives as of the
Effective Date.

For Halberd Logistics                For Cobalt Integrations LLC

By: ____________________________     By: ____________________________
Name: __________________________     Name: __________________________
Title: _________________________     Title: _________________________
Date: __________________________     Date: __________________________
"@
        }
    )

Write-Host ''
Write-Host 'Generated sample evidence PDFs:' -ForegroundColor Green
foreach ($r in $results) {
    $name = Split-Path $r.Path -Leaf
    Write-Host ("  {0,-25} {1,3} pages   {2,6:N0} bytes" -f $name, $r.Pages, $r.Bytes)
}

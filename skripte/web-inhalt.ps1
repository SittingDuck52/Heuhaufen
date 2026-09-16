# web-inhalt.ps1 - die Seite und die Datenfunktionen. Wird von web.ps1 und von puzzle.ps1 geladen
# (dot-sourcing), damit es nur eine Quelle fuer HTML und Schnittstellen gibt.
# Erwartet die Variable $WebOrdner mit dem Ordner, in dem status*.json und verlauf*.csv liegen.
if (-not $WebOrdner) { $WebOrdner = Join-Path (Split-Path $PSScriptRoot -Parent) 'daten' }
# Name und Versionsnummer: ersetzen {{APP}} und {{VERSION}} in der Seite (Fotos der Seite zeigen so die Fassung)
if (-not $AppName) { $AppName = 'Heuhaufen'; $AppVersion = '?' }
if (Test-Path (Join-Path $PSScriptRoot 'version.ps1')) { . (Join-Path $PSScriptRoot 'version.ps1') }
$inv = [Globalization.CultureInfo]::InvariantCulture
# Texte der Seite: ohne Dashboard (web.ps1) hier laden - wer die Datei laedt, hat meist schon sprache.ps1 geladen
if (-not (Get-Command Get-TexteJson -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'sprache.ps1') }
# ---------- Daten einsammeln ----------
function Read-Datei([string]$p) {
    # puzzle.ps1 ersetzt die Datei beim Schreiben; ein zweiter Versuch reicht immer
    for ($i = 0; $i -lt 3; $i++) {
        try { return [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) } catch { Start-Sleep -Milliseconds 60 }
    }
    ''
}

function Get-Stand {
    $liste = @()
    foreach ($f in @(Get-ChildItem (Join-Path $WebOrdner 'status*-gpu*.json') -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $t = Read-Datei $f.FullName
        if (-not $t) { continue }
        try { $o = $t | ConvertFrom-Json } catch { continue }
        $alter = [math]::Round(((Get-Date) - $f.LastWriteTime).TotalSeconds)
        $liste += ($o | Add-Member -NotePropertyName alter -NotePropertyValue $alter -PassThru -Force)
    }
    $liste
}

function Get-Verlauf([int]$max = 400) {
    $h = @{}
    foreach ($f in @(Get-ChildItem (Join-Path $WebOrdner 'verlauf*-gpu*.csv') -ErrorAction SilentlyContinue)) {
        if ($f.Name -notmatch '^verlauf\d+-(.+)-gpu(\d+)\.csv$') { continue }
        $key = "$($matches[1])-gpu$($matches[2])"
        $punkte = @()
        try {
            foreach ($z in @(Get-Content $f.FullName -Tail $max -ErrorAction SilentlyContinue)) {
                $s = $z -split ';'
                if ($s.Count -lt 4 -or $s[0] -eq 'zeit') { continue }
                $punkte += ,@($s[0], [double]::Parse($s[1], $inv), [double]::Parse($s[2], $inv), [double]::Parse($s[3], $inv))
            }
        } catch { }
        $h[$key] = $punkte
    }
    $h
}

# ---------- Die Seite ----------
$WebHtml = @'
<!DOCTYPE html>
<html lang="{{LANG}}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{APP}} {{VERSION}}</title>
<!-- ICON -->
<link rel="icon" type="image/png" sizes="32x32" href="data:image/png;base64,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">
<link rel="apple-touch-icon" sizes="72x72" href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAYAAABV7bNHAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAABiFSURBVHhe7VwHVFRX18UUNX5JTDFRo1ETgyFqVBI1URFURLEigvSuVJU+lEF6h6H3Lk2kSVEUG6iIqBFLRGNNNNZYUQQBwf2tcwdQHyCgJPH713/W2muGefees/ee294bExGR/483MvrMdJ75tlOW07tJJU79tMzkBsqrzx+iojd3KIHe02d0jdpQW26C/2vRR1xc/J0V2gsGe8dbTvJLsF7mGWPOi8xxiszcE5SXXRa8a0NJwP6MEkE5gd7TZ3QtMsspktpSH+9Iy0mUg3JRTm6R/7mYOXN4Pyt3jVH2/gbyMZtcApO3ee9O3yW4lFseVpNXHlafVxH6JK8ivLngUAQYDkcK0fI3XcurCHtCbalP+m7BJcpBufgBhssoN9Xg1n3To4+ivvSH9p4rp4dusHdP2Ox5YOOeoDu5ZSENeRXhyD8YzsRvPhKFomMx2HYiFsW/xmH7yfgXQJ/RNWpDbQsORbK+lINyZe4Luk25gzfYu1t7rpxONd/0UdVHVk32A56n3qzgNH5U2k7fi1l7Axtyy0OxqSIMBYcjUHQ0honfdToRu88koeTsepSeIyR3gvWsDbXd9Vsi60uGUS7KSbmpBtUKSbePtPVeKSWrNuWDN86oESNG9F3NVxf3X28Tkrzd53JmWeCT7P3ByDsYhi2VUSg+GYedpxKYyN4A5aKclDuvIgxUi2quL/a+JEjmBa/mK4mPmD+iL5fnvxF9FivP+dwp1MQ8frP7yYxS/4bMfYHIPRCCzZWRQmNOJ/ytoBpUi2pS7YwS/wbi4hJqYk7c/rXRRDsJfVMBqTapKdt97meU+jdnlwWi4Eg4tv0ag+1Vcf8otp2IQcEv4SAOxIU4ETdjR7UfWna9fy7Gjx8/wNJTWy4iZ1152k6fho17BMg9EIwtRyOZOcUnY/8VUG3iQKOJOBG3iGzHA9YeOkuJM1fH3xLTpo1539RFQy+2wPl86k7v5oxSf2w6GMKIFR2PeiNAXIgTcSOO0fnO583cNHWlpMT+w9XTqzFFdsoHVp6altGbHK+m7PTChj1+yDsUgs1HI95IELeMPX5I3eUN4mztoW1GGri6eiVo5FiQOXnrbibv8MSGUl9sOhSMgiNhr438X0LbfdZbIJOIK3GOzlt33dJd04K0cPW9VoiLD3lvrbO6bkQ2/2pSsTvSSryRWxGEvMMhr4XCXyKx43gyDp3biiMXdiD/cBgzndvudUFciTNxD8+xv0JaSBNX5yuFmJjYu6vXKS8Kz7I/m7jVDSm7vJBdHoDcg0FMTFegdqztQfo7hL3PqQjEliMxuHj9JB7U3kXjk3pUP7qDrZWJ7Fprn94EcSbupIG0rHFUWUjauHp7Gn1UjGQn+a232B9b6NxM30BmmT8T0R1kHwjApooQbKtMxP7T+Th8djs7PGbu90d+RSRu3b+C1iCTyqrysbHMn/Xj5uoNUG7SQFoEKZZlaiYLJ77WOWnG/ImDXCKME6PyHRvii1yRXuqDzP0CZJV3DWbCwQicu3aUjY7GJw2oqavG1iOJSN/jg/QSX1RdOoinT5+2WPQUVX8cxMa9wr7cfL0ByksaEopcEZnn2OAcbpQgI//zZ1zd3Qq6fTBxUjYKy7a7E1PohOSdnthY5tdtZOzzZSfba7cvto2SJ02NKK/agtTdXkja7o6So7loaKxvu37z7mVk7wvGhr0+7fL1JkgLaSJta1xUDYYP7/kTgbeUdOdN8F1vdiwyz6E5fqsL0vd4M9HdAQlMK/ViO0flmb1oftosHCNPn+LclWNsLUgqdkNWSTiqa+60GVRb/xBFhxKRVuKFjL1+2LhPgMx9AvZKf9PIo9wEbs2egLSQJtLmnWR6ZMUqGZpqb3FN6DRoG+T5avmEZtvUR+XzsX6nOxPcXaSWeCJltwcSi12x5UAy6hsft5lwq/oqMvcEI6HYBUlbPXHhalXbtaamJzhzuRKHz+zA6cuH8fuNU7h08zf8fqMKpy4dQllVAfIPRCGt1JvV4NbtCUhTVL4DQjNt6m38dHx7svW/pbRSZrpvkum58Bw7xBU5IXmXOxPcE1CfhG3OSNsuwO37N9pMqG+sQ9HBZCRv90R2aTjOXDrG1p/WoFH29Glzy9r0DPT3k6YnuPPgBipObxWebV6B1/P84rY4gTT6JJqdV9afN61bo0hcfNSH5h4aguAM68bwXHskFrtg/U63HiNphyvitzkjpsARZy8fa1uMSfyVvy7gjxu/4X7NbSa6p1HfUIvKcyVsLaE63NrdBWmLyLUHaTV3V/cn7Vw/uNFnkZrED+7RRieDN1ojutABidtdXg3FLkjYJpxGR8/uQ1NzU5vAZzvXq0dN3QNsPZyMhGLn9rV7gOgCB5BW92jjk6S9q22/n4nzClu/FLO6kCxrxBY5MgLdQfw2Jzal1m93Z2vMjiPpqDxXiqu3LqKu/hFNEq7G1woy+cyflUjcRiPVqR2f7oI0klb/VLO6Nc5KPPKAa0pr9Jk5b+xwuwDt7QEbLBCaw0Ns0bpugabSpv2RKDtZgPNXT+Duw5toaHzcrZFCU44OiXerb+HKzYu4eOU0Llw5hWu3LuFxQ+0L6xM37j28hYxdQYjZ7NCOU09AWkmzrUC7WFJ2/LDORtHby3WlpT3ijK77p5khPM8WMVscukT0Zj6Strnj0s0zaGp+0i1TKGjHunbrDxw4sQOZO6IQk+uB4HQ7+CWbM4Rm8JFfmvTCAs+N+oY6FJYlIjLfjpnE5dZdkFb/dDO4Jxhfk9eZPZu84JojIjJcpJ+e9VInzwSTOkG6OSLybRFVaN8lIvLtEJnHx/Gz5Vz+L42Hj+4jZXMQfNebwid5LfxSTUF1BRuE8Eszg2+yKYrKNqC+4dkx4fmgg+eW8mSE5fIQWdCeW3dBGqi2V8LqOl3rpXzygmtPn8FfDx5kG6hd6JW0ppkIkkGRBXYvBSUO22SDoExLFJWnsdsJWmuIOIlq/bujoClYuC+ZGRO40QIh2VYIybFGaI41ew3OtmTfakSWE27du8btzuJxfS1ySqIRnGWF8Dwb4ZfVAc+uQFpJM2m3EWjmkhfcafaW5ILx420EmlVeSSYIyDBHaK41wjbxugS1I4EJhV74/dpvOP37Uew4kIP0onBs2ZeOW/eud7iOkHF0yg7OEppBeZ5HSI4VyxuaaY+rt37ndmdx8+4VxOa5sS+ou3w7AvUlzaTd2k/jBHnBPRO9o2O5ZK5zxKq7ngkmCNxozgh2ByQuMNOcDdGILEf4JJrCPc4IbrGGcIs1wuY9aWxEdRS0BkXnOSMoy6LTvKlbA1Fdc5fblY3O0iMF8E8zZ+2oPTdHT0CaSbtz5Krb5AV58rxB/RRWzV3lEqVf55FgjICN5ox0d0EE/TeYwidlDbxTTNgrwTPRBDE57rj/8DZXH4vaxw+RsT0UggyzDnPGFrjg1O+/oPm5MxQFbQR/XDuDpEI/hGc7ICSbx9pzc/QEpNkj3hjO0atqyYsXtvvBgwcPWKYzy9UpXK/BI8EIggxTBGw06xGoD5nkv2Fty6spfFPXwD/Fkm3bHQWdovdUFsIvfS3rL6A8G80Qkm2DzF3hOH/l105G31N2trpb/Reu/nURxy/sR35ZHMJybJnZXG7dAdX3iDeCY/jKevKCPGn1p89XX334gYbpgijHcL0nHgmGQpEk+HWwYS1801bDM9EYe45sZtt6R3H20nEEbRCuAVGbnLBpTyyOnyvHg0f3un1koPXs0eMHOHRqN8Jz+fB7Ff4b1sI9wRDrInQbyQvypHWhfmv8jBEfmXkqZ68L0212jzeAb/qa10faavikmsAj0QDrCwWofVzD1cXifs0dlBzJw9EzZbh++zLq6mu7bQw3aF0qO17EdiSftNXtOXUB0u4QrttEXpAnrQv1W5Mnj/mEJ1Db6hCuA7e4VUxYb8A7xRjuCQYQpFizU3JHQWbQfRqdqHsj6PlS6lYBvJKN4JNq3I7Ty+AatwrkAXlBnrQZ9KOk6Kc2Qeo7+GFacIldCe8Uo16BV7Ih3BP04RpjgEMnS3s0Mmjtqa2rQXXNPdx7cBv3H9zBo7qHL9z0dhRk9P7j2+CdbALP9YbtOL0MpJ08IC/Ik1aD3qY/eAGqO+xCNOAUrQuPJINeg1vCKjhG6SJnZ3ynJ2IK2qloel27dRm/VO1FYWka4jf5ITCZD+84C/jEWyE22xtllcV4+Kia2/2FuHzjHARpFnBP1G/H52Ug7eSBlUC11SB2y/G26I+in5p5K27hBag1O0RqM1G9Bdf4lXCM1kFwGh93qv/iamFBj2SPni5HQq4/vOLMYB+sA+sAVfAC1WAbrA7bYA32Sn/bh+igoCQVjxvquGnags5NkVnOcInTg2vCynacOgNpJw/MPBW3kCetBr01dMzQT3RtFmRaCpSb7MM04BynC5d4vV6Bc6wuHKO04RptiKrzR7haWNDoKShJgU2gBmyC1GAfqgF+uBYcIrSwLkqb9adXh3AtZpRrlDEuXvmNm6YtaENI2RwAx2jtbmuhdqSdPCAvyJO2Nej9Ee9/JKcrEWnmq9RoE6wOxxhtOMXq9A5idLAuSgv2YZoo2pfR9gD/+aC16dTFSjhHrQI/XJO1J3EMMS2g91Ha7Do/VAcVJ3Z1uqbRGSmtKBQOkVrd1kLtSDt5QF6QJ20GiXwo8oHMiinr1nor1FsJVOAQqQnHaCLZO1gXqQnbEHXEZHuhpvYBVw8Lmn7B6fbgR2gwgzoDXXeM1MPR38o7NYhqxOZ4sREhNLtrkGbSTh6QF+RJq0F0GBqwQHWqpqmXwiMLvxWwD1dnHXoHGkyUbYgqmxqXr1/g6mFBv49tLI6EXZg6a0/9OspD3CKzXHDn/k1uira4eecqvBPMYBuq1kmu9qC8pH2t1/JH5IWIiAj9dt92R99PVnnKHGNnuRum3gqwCVaBfbhar8EuTA02ISqwDVJHWeW2Tr/58mPb2TpD7bk5hFBHSAafnb47mqoUtM2XH90Bu2BNVrPzXC+CNJN2A8el18kL7qPXd0eLfTlWy3LekTUey2EpWAHbUNVeBS9YGZYCJSQXBLETb0fx540L7AkAkX3WV/ienhBk74rBlb8utrt5fT5o9AQl82Hhv4KT5+UgzaRdw3L+QfKCPHneoHcGDBgwSN18ToaR29ImU+/l4AUrwSZEuVdA5lgHKcHCX5GdaW7dpWdE7aOmthpRWW6wDFgBXpAyHMK14Z9siU27E3DmjxNd3obQU4PUwlCY+whrUU2qzeXDBWk19ZYHaVcznZ1KXnAfd9Bi9P4s+Yk2+o6Lakzc5WApoAIregVWgSuYaHM/BVj5qeLXc4c7FEp39zsqchGUaoesHTE4XLUHf929yp4+vixoRF2/dRlJmwJh5qUIUx95WAgUYRXQnktHIK2kmbTPWj7JkrzgPjCjxaj/T9LfSmnZyPxh6LwIa72Xwdx/ea/CzE8eazzlsbk0vdMfDGkHol84hNOwvYnPB603D2urUXG8BD6xVjBxk8NqTzlWh1v7ZSCtpFmHJ/P75LlikuQF95ErxbufjXx/5HJDiRx9xwXNRq6LYeq7jBXrDVAugrmPIrbtz+z08Ud3gkYM3Z8d+nUPwtJcYOqhCAPnhTBxX4K1PnJttbgcOgK1I62kWcFgRvaQkR+N4K4/rUHH6g9myU800baRqV7luACrPYUFXxe0HtBJOjbXE6W/FOL+w2f/oqOnQfdhhSVp8Iwxh4mbPAmDoetCGHssxhrvpe1qdwXSSFpJ8+zlk4zIg45/9mmZZqMnfDFJ0Xhmha79POg7L8BqryWvDd9EC1y6fo7dAnR1N94atEbRze2DmnsvPFW8fe8mnEKNoMefD30nWRi6LoCxxyKYeC5uV7dLeC5hGkmrosnMA99M+mJCZ9OrNd4ZMEDk0zmKE/maPOlaXb4MDN0WsuKvAiJu5L4QXrFmnZ6gO4q6x49w8HgJEnMD4R1tiXOXTj67Vl+LuGw/oTluQnNaDeopyFwdvgw0rKXr5ihMsift3N2LG7RyDxgzadjk5cYzDmvZSjfrrSOTFjChPQX103eRBT9Yj+1GL8ZTNDc3M8F0dnn+7pymoFvkWmhYz4aO3TxsLklv2/XoteRgIYzdlsDAVbZdze6CuJE20rjcePovpJm0c3evjuLdAQNEBs1cOs5azVLyoabNbOg5zmNkegp9l/lY6TQPlr6q7Dd3Cpoud+7/hVMXjqJgdyoCEvlwCDZA1fnKtl2r8UkjkvKCoMufB207aYSkOLNR1RoX/jwNnkAdq5xfjRdBz1EGpE3VUvKhpNw4XsvZp8PFmRtsFH05+qOxi3Qn71S1kGwSmiTDCPUUeo5zYeK2DLsq8lF2ZDubNrSGGDguhpaNNNSspKBmNQs52xOZMcJR0owDx3bCwHkRtO3ngOevhSs3/2gziBZq33hrrHxlTq3mSDUt0plcPExs8Ljujp7WoHk4UFzqa2UFk2mXVSxmQsNmFnTXSTPBPYGOwxzo8KVh5LwUevwFULOUom8N6tZS0LSdxaDBmwXPaAt2pmmNP29chLW/BrTsZ2Olgyw767ROM5qW6VsioLuufb2uQBpIC2lSMJp2WVx6tBJp7Wrt4Qbb0fp93G/YLIXxvoprptUom0tAw0YK2vw5QtHdhDZ/NrTsZzFS6jzhK5lCnwmvzWafrXFTxPnLz34/ox0vIMm+xcQ5SMwJYKflY6crkF2cAIegVawv5eDW7AzEnTSQFtIkpTDe5+OP+9E/d3npztVZ0FngP8O+Gjh+rvLEbIXVPzcqmc2AOk+SiespNG2loGErBU07KWjZvXhNw1aSDfmd5Xlto4QOkplbY9gaRDUNHJeA56sNHbv5ULGQhJrVTNaPW+dloDykgbTMVZ2YRdpabis6PPd0J2jR+khs8nDJeeqT9smb/NykaDoNqtZCcr0FdZuZULGQQFiqK/68fhGVp8qxYXMU7AR6UOdJQY0nAVWrGVC2mAFl8xlQsZSAGq9nHIgzcScNpEVs0nC6paCnht1amDsLGnb0XOTTiTNGLluoLX5imfHUJoU1P0PFcgYj3ltQtpwBXXtZmHmqQIsnA2UzCSiZTYeK1QyoWrcHt//LQFyJM3FfqPvDcdJCmlq09XhqcYNW9vdE3hP5/HuJkSoLtMWr5AynNC03mYoV5tOgYjW9HfmegnIoW07DCrOfobj2JwZ6r2QhzP+qNagfcZQ3mQriLKst/itpIC0tTwy7vWt1FTRH3xPpLzJ4/PQv1eZrTDi6xOCHJ8uMJkNh7VQoWZCY3sEK858YuJ+/CojbMqMpIK7EmZnTX2RIizmvvO50Fm0mjZk6ZOlspXF7F6+c1LDE4AcsM/kRCqY0ooTi/m0QF+JE3Ijj7BXj9o75cchS4v53mdMaQpNERAaNHPeJlITct5kLdSc9XKwvzsgQqeVrJ0PBdMq/guVrpwiNMRQHcZLVmfBg+lLRzFFig2hBppPy32pOa7Sa9MmgLwZO+HHeKA9ptbEXZXXHP1mg9z0WG0yEnLE4lq3+AfJrfvxHQLWoJtUmDsSFOE2WGeU+6Iv+dIdOPwL+I+a0Bi1utAMM7Nu378hvfxysOF1udOFcze+q5+uMa5bVHY+FqyZgieFELDWexMjLmfQyjMVZ7sWGE1ktqkm1pTW+qyYuopMHKxO3llMyce21Bbm7QdsjnSHoP7X+bOCw974fL/GlhYS86H5pNbFHMlpjMU9rHCO+cOX3WGQwAYsNJ2CJ0cTXAuWgXJSTclMNqiWtLlYjsVy0fILkcEviQpxauBHH197KXydo2NJRfWD//iJDP//qgykTJYfxZiwbvWeOyrd356qPbZLRJLPG0jcMWd1xWKDXYpo+GSc0rz1arul/z9pSH+pLOSgX5aTcVINqfS85jEe1iUPLqCFO/9iU6iroG6KbPZrnA0X6iwwd8uWH4mI/DdGfPH/keoll35ycpTLm/hxV0UZp9W/BoPEt5mqIQUbru86h+R1rQ21b+81RE22kXDPkR1dNkR2ZLPbT0FVUi2q2nIyJwxv7P2Cief7MKBGRz/r27fv1UNGPJEb/8Km++Nzh0T8vGVUyTW7UOSkl0buzVERrpVS+qZdU+aZRUkX0iVQL6D19RtdYGyXRu9PkRp2lvpTjm0mfGX0p+pFE3/f7ft0ylagW1aTp9I+vNa8SrSOKhjndDNI3+5lIP5Ev+w98Z8IXXw+cM+bnwSvEpg41GzN1sPvYGUMjvpf8ImWC1BdpBHpPn9G1b3/63JTaUh/qSzlERNhJmHJSbqrxxo6YroJI0zdK3yztJLRo0rf9ccu5ZIhIP5FhtNv07dt3FAcj6RprI2xLfeg/eKMcZErraPmfNKajaDWLFk76nx+RYSSUnuSRaBoNz4M+o2vUhtpSH+r7j5ryX23cxBAN1tx9AAAAAElFTkSuQmCC">
<!-- /ICON -->
<style>
 :root {
   --bg:#0f1216; --karte:#171c22; --rand:#242c35; --text:#d8dee6; --grau:#8b97a6;
   --gruen:#3fbf6f; --gelb:#e0b64a; --rot:#e05a4a; --blau:#57a9e0; --balken:#0c1014;
 }
 * { box-sizing:border-box; }
 body { margin:0; background:var(--bg); color:var(--text);
        font-family:"Segoe UI",system-ui,sans-serif; font-size:15px; }
 header { padding:14px 18px; border-bottom:1px solid var(--rand); display:flex;
          flex-wrap:wrap; gap:6px 16px; align-items:baseline; justify-content:center; }
 h1 { font-size:17px; margin:0; font-weight:600; letter-spacing:.3px; }
 h1 .ver { font-size:12px; font-weight:400; color:var(--grau); margin-left:4px; letter-spacing:0; }
 .kopfwert { color:var(--grau); font-size:13px; }
 .kopfwert b { color:var(--text); font-weight:600; }
 main { padding:18px; display:grid; gap:16px; margin:0 auto; justify-content:center;
        grid-template-columns:repeat(auto-fit,minmax(290px,360px)); }
 .karte { background:var(--karte); border:1px solid var(--rand); border-radius:10px; padding:14px 16px; }
 .karte.alt { opacity:.55; }
 .kt { display:flex; align-items:center; gap:8px; margin-bottom:10px; }
 .kt h2 { font-size:15px; margin:0; font-weight:600; }
 .punkt { width:9px; height:9px; border-radius:50%; background:var(--grau); flex:none; }
 .zustand { margin-left:auto; font-size:12px; color:var(--grau); display:flex; align-items:center; gap:7px; }
 /* Der Punkt beginnt bei jeder Aktualisierung von vorn und blinkt so im Takt der Abfrage */
 .puls { width:8px; height:8px; border-radius:50%; flex:none; animation:puls 2s ease-out; }
 @keyframes puls { 0% { opacity:1; transform:scale(1.35); } 35% { opacity:.15; transform:scale(1); } 100% { opacity:.15; } }
 .fort { height:22px; background:var(--balken); border-radius:5px; position:relative; overflow:hidden; }
 .fort i { position:absolute; inset:0 auto 0 0; background:linear-gradient(90deg,#2f7d4f,#46c47a); }
 .fort span { position:absolute; inset:0; display:flex; align-items:center; justify-content:center;
              font-size:12px; font-variant-numeric:tabular-nums; }
 .werte { display:grid; grid-template-columns:1fr 1fr; gap:4px 14px; margin:12px 0 10px; font-size:13px; }
 .werte div { display:flex; justify-content:space-between; gap:8px; }
 .werte span:first-child { color:var(--grau); }
 .werte span:last-child { font-variant-numeric:tabular-nums; }
 .mini { display:grid; gap:5px; margin:10px 0; font-size:12px; }
 .mini > div { display:grid; grid-template-columns:74px 1fr 58px; align-items:center; gap:8px; }
 .mini b { font-weight:400; color:var(--grau); }
 .mini u { text-decoration:none; text-align:right; font-variant-numeric:tabular-nums; }
 .bar { height:7px; background:var(--balken); border-radius:4px; overflow:hidden; }
 .bar i { display:block; height:100%; background:var(--blau); }
 .zeile { font-size:12px; color:var(--grau); margin-top:8px; }
 .zeile b { color:var(--text); font-weight:600; }
 .ziel { margin-top:8px; font-size:11px; color:var(--grau); word-break:break-all; }
 .knoepfe { display:flex; gap:8px; margin-top:12px; flex-wrap:wrap; }
 button { font:inherit; font-size:13px; padding:7px 14px; border-radius:7px; cursor:pointer;
          border:1px solid var(--rand); background:#1e252d; color:var(--text); }
 button:hover { border-color:#3a4652; background:#232b34; }
 button:active { transform:translateY(1px); }
 button.los { border-color:#2f7d4f; color:#9fe6bd; }
 button:disabled { opacity:.4; cursor:default; }
 .meldung { margin-top:10px; font-size:12px; color:var(--gelb); min-height:16px; }
 svg { width:100%; height:64px; display:block; margin-top:10px; }
 .treffer { margin:18px auto 0; max-width:736px; padding:14px 16px; border-radius:10px;
            background:#2a1410; border:1px solid var(--rot); color:#ffd9d2; }
 .treffer b { color:#fff; }
 .leer { padding:40px 18px; color:var(--grau); text-align:center; }
</style>
</head>
<body>
<header>
  <h1>{{APP}}<span class="ver">{{VERSION}}</span></h1>
  <span class="kopfwert" id="kpuzzle"></span>
  <span class="kopfwert" id="ktempo"></span>
  <span class="kopfwert" id="kkarten"></span>
  <span class="kopfwert" id="kzeit"></span>
</header>
<div id="treffer"></div>
<main id="karten"></main>
<script>
var verlauf = {};
var L = {{TEXTE}}, LOC = '{{LOCALE}}';
function tx(k){ var s = (L[k] === undefined) ? k : L[k]; for (var i = 1; i < arguments.length; i++) s = s.split('{' + (i - 1) + '}').join(arguments[i]); return s; }

function n0(x){ return (x||0).toLocaleString(LOC,{maximumFractionDigits:0}); }
function n1(x){ return (x||0).toLocaleString(LOC,{minimumFractionDigits:1,maximumFractionDigits:1}); }
function n2(x){ return (x||0).toLocaleString(LOC,{minimumFractionDigits:2,maximumFractionDigits:2}); }

function dauer(s){
  if (s === null || s === undefined || isNaN(s) || s < 0) return '-';
  s = Math.floor(s);
  var t = Math.floor(s/86400), h = Math.floor(s%86400/3600), m = Math.floor(s%3600/60);
  if (t > 0) return t + (' ' + tx('web.tage') + ' ') + ('0'+h).slice(-2) + ':' + ('0'+m).slice(-2) + ' h';
  return ('0'+h).slice(-2) + ':' + ('0'+m).slice(-2) + ':' + ('0'+(s%60)).slice(-2);
}

function schluessel(x){
  if (x >= 1e15) return n2(x/1e15) + tx('web.brd');
  if (x >= 1e12) return n2(x/1e12) + tx('web.bio');
  if (x >= 1e9)  return n1(x/1e9)  + tx('web.mrd');
  return n0(x);
}

// Endzustaende bleiben lesbar, auch wenn die Statusdatei alt ist - danach schreibt ja niemand mehr
var ENDE = { beendet: tx('web.z.beendet'), gestoppt: tx('web.z.gestoppt'), crash: tx('web.z.crash'), solved: tx('web.z.geloest') };

function zustandText(d){
  if (d.zustand === 'found') return [tx('web.z.treffer'), 'var(--rot)'];
  if (ENDE[d.zustand]) return [ENDE[d.zustand], 'var(--grau)'];
  if (d.alter > 30) return [tx('web.z.keineDaten'), 'var(--rot)'];
  if (d.zustand === 'laeuft') return [tx('web.z.laeuft'), 'var(--gruen)'];
  if (d.zustand === 'pause-ollama') return [tx('web.z.pauseOllama'), 'var(--gelb)'];
  if (d.zustand === 'pause-vram') return [tx('web.z.pauseVram'), 'var(--gelb)'];
  if (d.zustand === 'pause' || d.zustand === 'pause-hand') return [tx('web.z.pauseHand'), 'var(--gelb)'];
  if (d.zustand === 'pause-wartet') return [tx('web.z.bereit'), 'var(--gelb)'];
  if (d.zustand === 'found') return [tx('web.z.treffer'), 'var(--rot)'];
  return [d.zustand, 'var(--grau)'];
}

function balken(name, wert, anteil, farbe){
  var p = Math.max(0, Math.min(100, anteil*100));
  return '<div><b>' + name + '</b><div class="bar"><i style="width:' + p.toFixed(1) + '%;background:' + farbe + '"></i></div><u>' + wert + '</u></div>';
}

function kurve(key){
  var p = verlauf[key];
  if (!p || p.length < 3) return '';
  var w = 300, h = 64, werte = p.map(function(x){ return x[1]/1e6; });
  var max = Math.max.apply(null, werte) * 1.1, min = 0;
  var schritt = w / (werte.length - 1);
  var d = werte.map(function(v,i){
    return (i?'L':'M') + (i*schritt).toFixed(1) + ' ' + (h - (v-min)/(max-min||1)*(h-6) - 3).toFixed(1);
  }).join(' ');
  return '<svg viewBox="0 0 ' + w + ' ' + h + '" preserveAspectRatio="none">' +
         '<path d="' + d + ' L ' + w + ' ' + h + ' L 0 ' + h + ' Z" fill="rgba(87,169,224,.13)"/>' +
         '<path d="' + d + '" fill="none" stroke="var(--blau)" stroke-width="1.5"/>' +
         '</svg><div class="zeile">' + tx('web.kurve', werte.length, n0(max/1.1)) + '</div>';
}

function karte(d){
  var z = zustandText(d), key = d.pc + '-gpu' + d.gpu, tempo = d.alter > 30 ? 0 : d.tempo;
  var h = '<div class="karte' + (d.alter > 30 ? ' alt' : '') + '"><div class="kt"><span class="punkt" style="background:' + z[1] + '"></span>' +
          '<h2>' + d.pc + ' &middot; GPU ' + d.gpu + '</h2><span class="zustand" style="color:' + z[1] + '">' + z[0] +
          '<span class="puls" style="background:' + z[1] + '"></span></span></div>';
  h += '<div class="fort"><i style="width:' + Math.min(100, d.anteil*100).toFixed(3) + '%"></i>' +
       '<span>' + (d.anteil*100).toLocaleString(LOC,{minimumFractionDigits:4,maximumFractionDigits:4}) + ' %</span></div>';
  h += '<div class="werte">' +
       '<div><span>' + tx('web.l.tempo') + '</span><span>' + n0(tempo/1e6) + ' MKey/s</span></div>' +
       '<div><span>' + tx('web.l.rest') + '</span><span>' + dauer(d.rest) + '</span></div>' +
       '<div><span>' + tx('web.l.geprueft') + '</span><span>' + schluessel(d.geprueft) + '</span></div>' +
       '<div><span>' + tx('web.l.laufzeit') + '</span><span>' + dauer(d.laufzeit) + '</span></div>' +
       '<div><span>' + tx('web.l.share') + '</span><span>' + n0(d.share) + '</span></div>' +
       '<div><span>' + tx('web.l.abgesucht') + '</span><span>' + n0(d.abgesucht) + '</span></div>' +
       '</div>';
  h += '<div class="mini">' +
       balken(tx('web.l.leistung'), n0(d.watt) + ' W', d.limit ? d.watt/d.limit : 0, 'var(--gruen)') +
       balken(tx('web.l.temperatur'), n0(d.grad) + ' °C', d.grad/90, d.grad >= 83 ? 'var(--rot)' : (d.grad >= 75 ? 'var(--gelb)' : 'var(--gruen)')) +
       balken(tx('web.l.luefter'), n0(d.luefter) + ' %', d.luefter/100, 'var(--blau)') +
       balken(tx('web.l.auslastung'), n0(d.last) + ' %', d.last/100, 'var(--blau)') +
       '</div>';
  h += '<div class="zeile">VRAM <b>' + n0(d.vram) + '</b> ' + tx('web.vram.von') + ' ' + n0(d.vramGesamt) + ' MB, ' + tx('web.vram.fremd') + ' <b>' + n0(d.vramFremd) + ' MB</b></div>';
  if (d.ollama) {
    if (!d.ollama.erreichbar) h += '<div class="zeile">' + tx('web.ollama.nichtErreichbar') + '</div>';
    else if (!d.ollama.modell) h += '<div class="zeile">' + tx('web.ollama.keinModell') + '</div>';
    else h += '<div class="zeile">Ollama <b>' + d.ollama.modell + '</b>, ' + n0(d.ollama.mb) + ' MB, ' +
              (d.ollama.aktiv ? '<b style="color:var(--gelb)">' + tx('web.ollama.rechnet') + '</b>' : tx('web.ollama.geparkt')) + '</div>';
  }
  h += '<div class="zeile">' + tx('web.sitzung', dauer(d.sitzung), n2(d.kwh), n2(d.kwh*d.preis)) + '</div>';
  h += '<div class="ziel">' + tx('web.ziel') + ' ' + d.adresse + '</div>';
  h += kurve(key);
  h += '<div class="meldung">' + (d.meldung || '') + '</div>';
  h += knoepfe(d);
  return h + '</div>';
}

function knoepfe(d){
  if (d.alter > 30 || ENDE[d.zustand] || d.zustand === 'found') return '';
  var ziel = " data-pc='" + d.pc + "' data-gpu='" + d.gpu + "' data-puzzle='" + d.puzzle + "'";
  var h = '<div class="knoepfe">';
  if (d.zustand === 'pause-wartet') h += '<button class="los" data-was="start"' + ziel + '>' + tx('web.k.start') + '</button>';
  else if (d.zustand.indexOf('pause') === 0) h += '<button class="los" data-was="weiter"' + ziel + '>' + tx('web.k.weiter') + '</button>';
  else if (d.zustand === 'laeuft') h += '<button data-was="pause"' + ziel + '>' + tx('web.k.pause') + '</button>';
  h += '<button data-was="auto"' + ziel + '>' + (d.automatik ? tx('web.k.autoAus') : tx('web.k.autoAn')) + '</button>';
  return h + '</div>';
}

function befehl(b){
  b.disabled = true;
  fetch('api/befehl', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ was: b.dataset.was, pc: b.dataset.pc, gpu: b.dataset.gpu, puzzle: b.dataset.puzzle })
  }).then(function(){ setTimeout(hole, 1200); }).catch(function(){ b.disabled = false; });
}

document.addEventListener('click', function(e){
  if (e.target && e.target.tagName === 'BUTTON' && e.target.dataset.was) befehl(e.target);
});

function zeichne(liste){
  var m = document.getElementById('karten');
  if (!liste.length) { m.innerHTML = '<div class="leer">' + tx('web.leer') + '</div>'; return; }
  m.innerHTML = liste.map(karte).join('');
  var tempo = 0, watt = 0, treffer = [];
  liste.forEach(function(d){
    if (d.alter <= 30) { tempo += d.tempo || 0; watt += d.watt || 0; }
    if (d.treffer) treffer.push(d.pc + ', GPU ' + d.gpu + ', ' + tx('web.datei') + ' ' + d.trefferDatei);
  });
  document.getElementById('kpuzzle').innerHTML = 'Puzzle <b>' + liste[0].puzzle + '</b>';
  document.getElementById('ktempo').innerHTML = tx('web.zusammen', n0(tempo/1e6), n0(watt));
  document.getElementById('kkarten').innerHTML = liste.length + (liste.length === 1 ? tx('web.karte') : tx('web.karten'));
  document.getElementById('kzeit').textContent = tx('web.stand', new Date().toLocaleTimeString(LOC));
  document.getElementById('treffer').innerHTML = treffer.length
    ? '<div class="treffer"><b>' + tx('web.treffer') + '</b> ' + treffer.join(' / ') +
      '<br>' + tx('web.trefferHinweis') + '</div>'
    : '';
}

function hole(){
  // Ist das Suchfenster zu, antwortet niemand mehr: letzter Stand bleibt stehen, oben steht seit wann
  fetch('api/status').then(function(r){ return r.json(); }).then(zeichne).catch(function(){
    var k = document.getElementById('kzeit');
    if (k && k.textContent.indexOf(tx('web.keineVerbindung')) < 0) k.textContent = tx('web.keineVerbindungSeit', new Date().toLocaleTimeString(LOC));
  });
}
function holeVerlauf(){
  fetch('api/verlauf').then(function(r){ return r.json(); }).then(function(v){ verlauf = v; }).catch(function(){});
}
holeVerlauf(); hole();
setInterval(hole, 2000);
setInterval(holeVerlauf, 60000);
</script>
</body>
</html>
'@
# Beantwortet eine einzelne Anfrage. Wird von web.ps1 und vom Dashboard gleichermassen benutzt.
function Invoke-WebAnfrage($ctx) {
    $pfad = $ctx.Request.Url.AbsolutePath.TrimEnd('/')
    $typ  = 'text/html; charset=utf-8'
    $txt  = ''
    switch ($pfad) {
        ''             { $txt = $WebHtml.Replace('{{APP}}', "$AppName").Replace('{{VERSION}}', "$AppVersion").Replace('{{LANG}}', "$Sprache").Replace('{{LOCALE}}', $Kultur.Name).Replace('{{TEXTE}}', (Get-TexteJson 'web.')) }
        '/api/status'  {
            $typ = 'application/json; charset=utf-8'
            $arr = @(Get-Stand)
            # ConvertTo-Json macht aus einem einzelnen Element kein Array - die Seite will aber immer eins
            $txt = if ($arr.Count -eq 0) { '[]' }
                   elseif ($arr.Count -eq 1) { '[' + (ConvertTo-Json $arr[0] -Depth 5 -Compress) + ']' }
                   else { ConvertTo-Json $arr -Depth 5 -Compress }
        }
        '/api/verlauf' { $typ = 'application/json; charset=utf-8'; $txt = ConvertTo-Json (Get-Verlauf) -Depth 5 -Compress }
        '/api/befehl'  {
            # Knopf auf der Seite: legt eine Befehlsdatei fuer das passende Fenster an.
            # Nur POST, damit kein Vorschaubild oder Suchdienst versehentlich etwas ausloest.
            $typ = 'application/json; charset=utf-8'
            $txt = '{"ok":false}'
            if ($ctx.Request.HttpMethod -eq 'POST') {
                $leser = New-Object IO.StreamReader($ctx.Request.InputStream, [Text.Encoding]::UTF8)
                $roh = $leser.ReadToEnd(); $leser.Close()
                try { $d = $roh | ConvertFrom-Json } catch { $d = $null }
                $was = "$($d.was)".ToLower()
                $pc  = "$($d.pc)"
                $gpu = "$($d.gpu)"
                $puz = "$($d.puzzle)"
                # streng pruefen: nur bekannte Befehle und saubere Namen kommen durch
                if ($was -in @('pause','weiter','start','auto') -and
                    $pc -match '^[A-Za-z0-9_\-]{1,32}$' -and $gpu -match '^\d{1,2}$' -and $puz -match '^\d{1,3}$') {
                    try {
                        Set-Content -Encoding ascii -Path (Join-Path $WebOrdner "befehl$puz-$pc-gpu$gpu.txt") -Value $was
                        $txt = '{"ok":true}'
                    } catch { }
                }
            }
        }
        default        { $ctx.Response.StatusCode = 404; $txt = '<h1>404</h1>' }
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes($txt)
    $ctx.Response.ContentType = $typ
    try { $ctx.Response.Headers.Add('Cache-Control', 'no-store') } catch { }
    $ctx.Response.ContentLength64 = $bytes.Length
    try { $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length) } catch { }
    try { $ctx.Response.Close() } catch { }
    $pfad
}
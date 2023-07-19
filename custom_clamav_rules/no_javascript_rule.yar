
rule javascript_found : PDF raw
{
	strings:
		$reg1 = "</Javascript" nocase
		$reg2 = "</JS" nocase
		$reg3 = "/JS" nocase
		$reg4 = "/Javascript" nocase
	condition:
		$reg1 or $reg2 or $reg3 or $reg4
}
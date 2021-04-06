
rule javascript_found : PDF raw
{
	strings:
		$reg1 = "/Javascript" nocase
		$reg2 = "/JS" nocase
	condition:
		$reg1 or $reg2
}
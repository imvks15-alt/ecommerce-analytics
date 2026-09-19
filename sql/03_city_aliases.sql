-- =========================================================
-- OLIST E-COMMERCE DATABASE
-- NORMALIZED REFERENCE TABLE
-- =========================================================

/*
Normalized city reference table was built to normalize city names across customers, sellers, and geolocation. It handled:

- Punctuation and whitespace variation
- Trailing state codes (e.g., "sao paulo sp")
- Accent removal (e.g., "São Paulo" → "sao paulo")
- Approximately 90 known variations of Brazilian city names
- Invalid values (numeric, email-like, empty) flagged as NULL
*/

USE olist_ecommerce; 			-- selecting database

-- =========================================================
-- CITY ALIASES
-- ==========================================================
DROP TABLE IF EXISTS city_aliases;
CREATE TABLE city_aliases (
    alias_id INT AUTO_INCREMENT PRIMARY KEY,
    original_city VARCHAR(100) NOT NULL,
    normalized_city VARCHAR(100) ,
    state_code CHAR(2) NOT NULL,
    state_name CHAR(100),

    UNIQUE KEY uq_alias_state (original_city, state_code)
);


-- ingesting raw city & state from staging table.

TRUNCATE TABLE olist_ecommerce.city_aliases;

INSERT INTO olist_ecommerce.city_aliases (
    original_city,
    state_code
)
SELECT DISTINCT
	LOWER(TRIM(customer_city)),
	TRIM(customer_state)
FROM olist_ecommerce.staging_customers
WHERE TRIM(customer_city) <> ''

UNION

SELECT DISTINCT
    LOWER(TRIM(seller_city)),
    TRIM(seller_state)
FROM olist_ecommerce.staging_sellers
WHERE TRIM(seller_city) <> ''

UNION

SELECT DISTINCT
    LOWER(TRIM(geolocation_city)),
    TRIM(geolocation_state)
FROM olist_ecommerce.staging_geolocation
WHERE TRIM(geolocation_city) <> '';

-- =========================================================
-- NORMALIZE EVERY STATE NAMES
-- =========================================================
UPDATE olist_ecommerce.city_aliases
SET state_name = CASE state_code
    WHEN 'AC' THEN 'Acre'
    WHEN 'AL' THEN 'Alagoas'
    WHEN 'AP' THEN 'Amapá'
    WHEN 'AM' THEN 'Amazonas'
    WHEN 'BA' THEN 'Bahia'
    WHEN 'CE' THEN 'Ceará'
    WHEN 'DF' THEN 'Distrito Federal'
    WHEN 'ES' THEN 'Espírito Santo'
    WHEN 'GO' THEN 'Goiás'
    WHEN 'MA' THEN 'Maranhão'
    WHEN 'MT' THEN 'Mato Grosso'
    WHEN 'MS' THEN 'Mato Grosso do Sul'
    WHEN 'MG' THEN 'Minas Gerais'
    WHEN 'PA' THEN 'Pará'
    WHEN 'PB' THEN 'Paraíba'
    WHEN 'PR' THEN 'Paraná'
    WHEN 'PE' THEN 'Pernambuco'
    WHEN 'PI' THEN 'Piauí'
    WHEN 'RJ' THEN 'Rio de Janeiro'
    WHEN 'RN' THEN 'Rio Grande do Norte'
    WHEN 'RS' THEN 'Rio Grande do Sul'
    WHEN 'RO' THEN 'Rondônia'
    WHEN 'RR' THEN 'Roraima'
    WHEN 'SC' THEN 'Santa Catarina'
    WHEN 'SP' THEN 'São Paulo'
    WHEN 'SE' THEN 'Sergipe'
    WHEN 'TO' THEN 'Tocantins'
    ELSE NULL
END;

-- =========================================================
-- BASIC FORMATTING (Remove punctuation and normalize spaces)
-- =========================================================
UPDATE olist_ecommerce.city_aliases
SET normalized_city = 
		TRIM(REGEXP_REPLACE(original_city,'[,/\\-.\\*]+',' '));

-- =========================================================
-- REMOVE EXTRA SPACES
-- =========================================================
UPDATE olist_ecommerce.city_aliases
SET normalized_city =
				TRIM(REGEXP_REPLACE(normalized_city,'\\s+',' '));

-- =========================================================
-- REMOVE STATE CODE FROM END OF CITY
-- Example: "sao paulo sp" -> "sao paulo"
-- =========================================================
UPDATE olist_ecommerce.city_aliases
SET normalized_city =
    CASE
        WHEN REGEXP_SUBSTR(normalized_city,'[a-z]+$') = LOWER(state_code)
        THEN TRIM(REGEXP_REPLACE(normalized_city,CONCAT('\\s',LOWER(state_code),'$'),''))
        ELSE normalized_city
    END;

-- =========================================================
-- USE VALUE INSIDE PARENTHESES
-- Example: "sao paulo (capital)" -> "capital"
-- =========================================================
UPDATE olist_ecommerce.city_aliases
SET normalized_city =
    CASE
        WHEN REGEXP_SUBSTR(normalized_city,'\\([^)]*\\)') IS NOT NULL
        THEN REGEXP_REPLACE(REGEXP_SUBSTR(normalized_city,'\\([^)]*\\)'),'[()]','')
        ELSE TRIM(normalized_city)
    END;

-- =========================================================
-- REMOVE ACCENTS / DIACRITICS
-- =========================================================
UPDATE olist_ecommerce.city_aliases
SET normalized_city =
    REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    REGEXP_REPLACE(
                                        REGEXP_REPLACE(
                                            REGEXP_REPLACE(
                                                REGEXP_REPLACE(
                                                    REGEXP_REPLACE(
                                                        REGEXP_REPLACE(
                                                            REGEXP_REPLACE(
                                                                REGEXP_REPLACE(
                                                                    REGEXP_REPLACE(
                                                                        REGEXP_REPLACE(
                                                                            REGEXP_REPLACE(
                                                                                REGEXP_REPLACE(
                                                                                    REGEXP_REPLACE(
                                                                                        LOWER(normalized_city),
                                                                                        '[áàâãäåāăą]', 'a'),
                                                                                    '[çćĉċč]', 'c'),
                                                                                '[ďđ]', 'd'),
                                                                            '[éèêëēĕėęě]', 'e'),
                                                                        '[ĝğġģ]', 'g'),
                                                                    '[ĥħ]', 'h'),
                                                                '[íìîïĩīĭį]', 'i'),
                                                            '[ĵ]', 'j'),
                                                        '[ķ]', 'k'),
                                                    '[ĺļľŀł]', 'l'),
                                                '[ñńņň]', 'n'),
                                            '[óòôõöøōŏő]', 'o'),
                                        '[ŕŗř]', 'r'),
                                    '[śŝşš]', 's'),
                                '[ťţŧ]', 't'),
                            '[úùûüũūŭůűų]', 'u'),
                        '[ŵ]', 'w'),
                    '[ýÿŷ]', 'y'),
                '[źżž]', 'z');

-- =========================================================
-- REMOVE EXTRA SPACES AGAIN
-- =========================================================
UPDATE olist_ecommerce.city_aliases
SET normalized_city =
    TRIM(REGEXP_REPLACE(normalized_city,'\\s+',' '));

-- =========================================================
-- HANDLE KNOWN CITY VARIATIONS
-- =========================================================
UPDATE olist_ecommerce.city_aliases
SET normalized_city =
    CASE
        -- =============================================
        -- SAO PAULO - SP
        -- =============================================
        WHEN normalized_city IN (
            'sao paulo',
            'saopaulo',
            'sao paulop',
            'sao pauo',
            'sa£o paulo',
            'sao paluo',
            'sp')
			AND state_code = 'SP'
        THEN 'sao paulo'

        -- =============================================
        -- SAO BERNARDO DO CAMPO - SP
        -- =============================================
        WHEN normalized_city IN (
            'sbc',
            'sao bernardo do campo',
            'sao bernardo do capo',
            'ao bernardo do campo')
			AND state_code = 'SP'
        THEN 'sao bernardo do campo'

        -- =============================================
        -- SAO JOSE DO RIO PRETO - SP
        -- =============================================
        WHEN normalized_city IN (
            'sao jose do rio preto',
            'sao jose do rio pret',
            's jose do rio preto')
			AND state_code = 'SP'
        THEN 'sao jose do rio preto'

        -- =============================================
        -- RIBEIRAO PRETO - SP
        -- =============================================
        WHEN normalized_city IN (
            'ribeirao preto',
            'ribeirao pretp',
            'riberao preto',
            'robeirao preto')
			AND state_code = 'SP'
        THEN 'ribeirao preto'

        -- =============================================
        -- MOGI DAS CRUZES - SP
        -- =============================================
        WHEN normalized_city IN (
            'mogi das cruzes',
            'mogi das cruses',
            'mogidascruzes')
			AND state_code = 'SP'
        THEN 'mogi das cruzes'

        -- =============================================
        -- SAO JOAO DO PAU D'ALHO - SP
        -- =============================================
        WHEN normalized_city IN (
            'sao joao do pau d alho',
            'sao joao do pau dalho',
            'sao joao do pau d''alho')
			AND state_code = 'SP'
        THEN 'sao joao do pau dalho'

        -- =============================================
        -- SANTA BARBARA D'OESTE - SP
        -- =============================================
        WHEN normalized_city IN (
            'santa barbara d oeste',
            'santa barbara d''oeste',
            'santa barbara d`oeste',
            'santa barbara d´oeste',
            'santa barbara doeste')
			AND state_code = 'SP'
        THEN 'santa barbara doeste'

        -- =============================================
        -- SANTA RITA D'OESTE - SP
        -- =============================================
        WHEN normalized_city IN (
            'santa rita d oeste',
            'santa rita d''oeste',
            'santa rita doeste')
			AND state_code = 'SP'
        THEN 'santa rita doeste'

        -- =============================================
        -- APARECIDA D'OESTE - SP
        -- =============================================
        WHEN normalized_city IN (
            'aparecida d oeste',
            'aparecida d''oeste',
            'aparecida doeste')
			AND state_code = 'SP'
        THEN 'aparecida doeste'

        -- =============================================
        -- PALMEIRA D'OESTE - SP
        -- =============================================
        WHEN normalized_city IN (
            'palmeira d oeste',
            'palmeira d''oeste',
            'palmeira doeste')
			AND state_code = 'SP'
        THEN 'palmeira doeste'

        -- =============================================
        -- ESTRELA D'OESTE - SP
        -- =============================================
        WHEN normalized_city IN (
            'estrela d oeste',
            'estrela d''oeste',
            'estrela doeste')
        AND state_code = 'SP'
        THEN 'estrela doeste'

        -- =============================================
        -- SAO LUIS DO PARAITINGA - SP
        -- =============================================
        WHEN normalized_city IN (
            'sao luis do paraitinga',
            'sao luiz do paraitinga')
			AND state_code = 'SP'
        THEN 'sao luis do paraitinga'

        -- =============================================
        -- PORTO FERREIRA - SP
        -- =============================================
        WHEN normalized_city IN (
            'porto ferreira',
            'portoferreira')
			AND state_code = 'SP'
        THEN 'porto ferreira'

        -- =============================================
        -- TABOAO DA SERRA - SP
        -- =============================================
        WHEN normalized_city IN (
            'tabao da serra',
            'taboao da serra')
			AND state_code = 'SP'
        THEN 'taboao da serra'

        -- =============================================
        -- EMBU GUACU - SP
        -- =============================================
        WHEN normalized_city IN (
            'embu guacu',
            'embuguacu')
			AND state_code = 'SP'
        THEN 'embu guacu'

        -- =============================================
        -- GUARULHOS - SP
        -- =============================================
        WHEN normalized_city IN (
            'guarulhos',
            'garulhos')
			AND state_code = 'SP'
        THEN 'guarulhos'

        -- =============================================
        -- SAO JOSE DO RIO PARDO - SP
        -- =============================================
        WHEN normalized_city IN (
            'sao jose do rio pardo',
            'scao jose do rio pardo')
			AND state_code = 'SP'
        THEN 'sao jose do rio pardo'

        -- =============================================
        -- BELO HORIZONTE - MG
        -- =============================================
        WHEN normalized_city IN (
            'belo horizonte',
            'belo horizont',
            'belo horizonta',
            'bh')
			AND state_code = 'MG'
        THEN 'belo horizonte'

        -- =============================================
        -- GOUVEIA - MG
        -- =============================================
        WHEN normalized_city IN (
            'gouvea',
            'gouveia')
			AND state_code = 'MG'
        THEN 'gouveia'

        -- =============================================
        -- PINGO D'AGUA - MG
        -- =============================================
        WHEN normalized_city IN (
            'pingo d agua',
            'pingo d''agua')
			AND state_code = 'MG'
        THEN 'pingo d agua'

        -- =============================================
        -- OLHOS D'AGUA - MG
        -- =============================================
        WHEN normalized_city IN (
            'olhos d agua',
            'olhos d''agua')
			AND state_code = 'MG'
        THEN 'olhos d agua'

        -- =============================================
        -- BRAZOPOLIS - MG
        -- =============================================
        WHEN normalized_city IN (
            'brazopolis',
            'brasopolis')
			AND state_code = 'MG'
        THEN 'brazopolis'

        -- =============================================
        -- RIO DE JANEIRO - RJ
        -- =============================================
        WHEN normalized_city IN (
            'rio de janeiro',
            'rio janeiro',
            'rio de janeiro io de janeiro',
            'rio de janeiro rio de janeiro',
            'rio de janeiro rio de janeiro brasil',
            'rj')
			AND state_code = 'RJ'
        THEN 'rio de janeiro'

        -- =============================================
        -- ARMacao DOS BUZIOS - RJ
        -- =============================================
        WHEN normalized_city IN (
            'armacao de buzios',
            'armacao dos buzios',
            'buzios')
			AND state_code = 'RJ'
        THEN 'armacao dos buzios'

        -- =============================================
        -- CAMPOS DOS GOYTACAZES - RJ
        -- =============================================
        WHEN normalized_city IN (
            'campos dos goytacaze',
            'campos dos goytacazes')
			AND state_code = 'RJ'
        THEN 'campos dos goytacazes'

        -- =============================================
        -- TRAJANO DE MORAES - RJ
        -- =============================================
        WHEN normalized_city IN (
            'trajano de moraes',
            'trajano de morais')
			AND state_code = 'RJ'
        THEN 'trajano de moraes'

        -- =============================================
        -- TERESOPOLIS - RJ
        -- =============================================
        WHEN normalized_city IN (
            'teresopolis',
            '´teresopolis')
			AND state_code = 'RJ'
        THEN 'teresopolis'

        -- =============================================
        -- ALTA FLORESTA D'OESTE - RO
        -- =============================================
        WHEN normalized_city IN (
            'alta floresta d''oeste',
            'alta floresta do oeste',
            'alta floresta doeste')
			AND state_code = 'RO'
        THEN 'alta floresta do oeste'

        -- =============================================
        -- NOVA BRASILANDIA D'OESTE - RO
        -- =============================================
        WHEN normalized_city IN (
            'nova brasilandia d oeste',
            'nova brasilandia d''oeste',
            'nova brasilandia doeste')
			AND state_code = 'RO'
        THEN 'nova brasilandia do oeste'

        -- =============================================
        -- SANTA LUZIA D'OESTE - RO
        -- =============================================
        WHEN normalized_city IN (
            'santa luzia doeste',
            'santa luzia d''oeste')
			AND state_code = 'RO'
        THEN 'santa luzia do oeste'

        -- =============================================
        -- MACHADINHO D'OESTE - RO
        -- =============================================
        WHEN normalized_city IN (
            'machadinho d oeste',
            'machadinho d''oeste',
            'machadinho doeste')
			AND state_code = 'RO'
        THEN 'machadinho do oeste'

        -- =============================================
        -- ALVORADA D'OESTE - RO
        -- =============================================
        WHEN normalized_city IN (
            'alvorada do oeste',
            'alvorada d''oeste')
			AND state_code = 'RO'
        THEN 'alvorada do oeste'

        -- =============================================
        -- QUARTO CENTENARIO - PR
        -- =============================================
        WHEN normalized_city IN (
            '4o centenario',
            '4º centenario')
			AND state_code = 'PR'
        THEN 'quarto centenario'

        -- =============================================
        -- SAO JOSE DOS PINHAIS - PR
        -- =============================================
        WHEN normalized_city IN (
            'sao jose dos pinhais',
            'sao jose dos pinhas')
			AND state_code = 'PR'
        THEN 'sao jose dos pinhais'

        -- =============================================
        -- SAO JORGE D'OESTE - PR
        -- =============================================
        WHEN normalized_city IN (
            'sao jorge doeste',
            'sao jorge d oeste',
            'sao jorge d''oeste',
            'sao jorge do oeste')
			AND state_code = 'PR'
        THEN 'sao jorge do oeste'

        -- =============================================
        -- ITAPEJARA D'OESTE - PR
        -- =============================================
        WHEN normalized_city IN (
            'itapejara d oeste',
            'itapejara d''oeste')
			AND state_code = 'PR'
        THEN 'itapejara do oeste'

        -- =============================================
        -- DIAMANTE D'OESTE - PR
        -- =============================================
        WHEN normalized_city IN (
            'diamante d oeste',
            'diamante d''oeste')
			AND state_code = 'PR'
        THEN 'diamante do oeste'

        -- =============================================
        -- PEROLA D'OESTE - PR
        -- =============================================
        WHEN normalized_city IN (
            'perola doeste',
            'perola d''oeste')
			AND state_code = 'PR'
        THEN 'perola do oeste'

        -- =============================================
        -- RANCHO ALEGRE D'OESTE - PR
        -- =============================================
        WHEN normalized_city IN (
            'rancho alegre d oeste',
            'rancho alegre d''oeste')
			AND state_code = 'PR'
        THEN 'rancho alegre do oeste'

        -- =============================================
        -- PAICANDU - PR
        -- =============================================
        WHEN normalized_city IN (
            'paicandu',
            'paincandu')
			AND state_code = 'PR'
        THEN 'paicandu'

        -- =============================================
        -- CASCAVEL - PR
        -- =============================================
        WHEN normalized_city IN (
            'cascavel',
            'cascavael')
			AND state_code = 'PR'
        THEN 'cascavel'

        -- =============================================
        -- FLORIANOPOLIS - SC
        -- =============================================
        WHEN normalized_city IN (
            'florianopolis',
            'floranopolis')
			AND state_code = 'SC'
        THEN 'florianopolis'

        -- =============================================
        -- BALNEARIO CAMBORIU - SC
        -- =============================================
        WHEN normalized_city IN (
            'balneario camboriu',
            'balenario camboriu')
			AND state_code = 'SC'
        THEN 'balneario camboriu'

        -- =============================================
        -- BALNEARIO PICARRAS - SC
        -- =============================================
        WHEN normalized_city IN (
            'balneario de picarras',
            'balneario picarras')
			AND state_code = 'SC'
        THEN 'balneario picarras'

        -- =============================================
        -- HERVAL D'OESTE - SC
        -- =============================================
        WHEN normalized_city IN (
            'herval d oeste',
            'herval d'' oeste',
            'herval d''oeste',
            'herval doeste')
			AND state_code = 'SC'
        THEN 'herval do oeste'

        -- ============================================
        -- SAO MIGUEL D'OESTE - SC
        -- =============================================
        WHEN normalized_city IN (
            'sao miguel d''oeste',
            'sao miguel do oeste')
			AND state_code = 'SC'
        THEN 'sao miguel do oeste'

        -- =============================================
        -- SANTANA DO LIVRAMENTO - RS
        -- =============================================
        WHEN normalized_city IN (
            'santana do livramento',
            'sant''ana do livramento')
			AND state_code = 'RS'
        THEN 'santana do livramento'

        -- =============================================
        -- BARRA DO QUARAI - RS
        -- =============================================
        WHEN normalized_city IN (
            'barra do quarai',
            'barrado quarai')
			AND state_code = 'RS'
        THEN 'barra do quarai'

        -- =============================================
        -- XANGRI-LA - RS
        -- =============================================
        WHEN normalized_city IN (
            'xangri la',
            'xangrila')
			AND state_code = 'RS'
        THEN 'xangri la'

        -- =============================================
        -- PORTO ALEGRE - RS
        -- =============================================
        WHEN normalized_city IN (
            'porto alegre',
            'porto aelgre')
			AND state_code = 'RS'
        THEN 'porto alegre'

        -- =============================================
        -- VILA BELA DA SANTISSIMA TRINDADE - MT
        -- =============================================
        WHEN normalized_city IN (
            'vila bela da santissima trindade',
            'vila bela da santssima trindade')
			AND state_code = 'MT'
        THEN 'vila bela da santissima trindade'

        -- =============================================
        -- FIGUEIROPOLIS D'OESTE - MT
        -- =============================================
        WHEN normalized_city IN (
            'figueiropolis d oeste',
            'figueiropolis d''oeste',
            'figueiropolis doeste')
			AND state_code = 'MT'
        THEN 'figueiropolis do oeste'

        -- =============================================
        -- MIRASSOL D'OESTE - MT
        -- =============================================
        WHEN normalized_city IN (
            'mirassol d oeste',
            'mirassol d''oeste',
            'mirassol doeste')
			AND state_code = 'MT'
        THEN 'mirassol do oeste'

        -- =============================================
        -- LAMBARI D'OESTE - MT
        -- =============================================
        WHEN normalized_city IN (
            'lambari d''oeste',
            'lambari doeste')
			AND state_code = 'MT'
        THEN 'lambari do oeste'

        -- =============================================
        -- SAO JOAO D'ALIanca - GO
        -- =============================================
        WHEN normalized_city IN (
            'sao joao dalianca',
            'sao joao d alianca',
            'sao joao d''alianca')
			AND state_code = 'GO'
        THEN 'sao joao d alianca'

        -- =============================================
        -- SAO ROQUE DO CANAA - ES
        -- =============================================
        WHEN normalized_city IN (
            'sao roque do canaa',
            'sao roque do cannaa')
			AND state_code = 'ES'
        THEN 'sao roque do canaa'

        -- =============================================
        -- LINHARES - ES
        -- =============================================
        WHEN normalized_city IN (
            'linhares',
            'linharesl')
			AND state_code = 'ES'
        THEN 'linhares'

        -- =============================================
        -- DIAS D'AVILA - BA
        -- =============================================
        WHEN normalized_city IN (
            'dias d avila',
            'dias d''avila',
            'dias davila')
			AND state_code = 'BA'
        THEN 'dias d avila'

        -- =============================================
        -- ARRAIAL D'AJUDA - BA
        -- =============================================
        WHEN normalized_city IN (
            'arraial d ajuda',
            'arraial d''ajuda')
			AND state_code = 'BA'
        THEN 'arraial d ajuda'

        -- =============================================
        -- MUQUEM DO SAO FRANCISCO - BA
        -- =============================================
        WHEN normalized_city IN (
            'muquem de sao francisco',
            'muquem do sao francisco')
			AND state_code = 'BA'
        THEN 'muquem do sao francisco'

        -- =============================================
        -- OLHO D'AGUA DAS CUNHAS - MA
        -- =============================================
        WHEN normalized_city IN (
            'olho d agua das cunhas',
            'olho d''agua das cunhas',
            'olho dagua das cunhas')
			AND state_code = 'MA'
        THEN 'olho d agua das cunhas'

        -- =============================================
        -- SENADOR LA ROCQUE - MA
        -- =============================================
        WHEN normalized_city IN (
            'senador la roque',
            'senador la rocque')
			AND state_code = 'MA'
        THEN 'senador la roque'

        -- =============================================
        -- OLHO D'AGUA GRANDE - AL
        -- =============================================
        WHEN normalized_city IN (
            'olho d agua grande',
            'olho d''agua grande',
            'olho dagua grande')
			AND state_code = 'AL'
        THEN 'olho d agua grande'

        -- =============================================
        -- OLHO D'AGUA DAS FLORES - AL
        -- =============================================
        WHEN normalized_city IN (
            'olho d agua das flores',
            'olho d''agua das flores')
			AND state_code = 'AL'
        THEN 'olho d agua das flores'

        -- =============================================
        -- OLHO D'AGUA DO BORGES - RN
        -- =============================================
        WHEN normalized_city IN (
            'olho d agua do borges',
            'olho d''agua do borges')
			AND state_code = 'RN'
        THEN 'olho d agua do borges'

        -- =============================================
        -- JUAZEIRO DO NORTE - CE
        -- =============================================
        WHEN normalized_city IN (
            'juazeiro do norte',
            'juzeiro do norte')
			AND state_code = 'CE'
        THEN 'juazeiro do norte'

        -- =============================================
        -- RIO BRANCO - AC
        -- =============================================
        WHEN normalized_city IN (
            'rio branco',
            'rio bracnco' )
			AND state_code = 'AC'
        THEN 'rio branco'

        -- =============================================
        -- JABOATAO DOS GUARARAPES - PE
        -- =============================================
        WHEN normalized_city IN (
            'jaboatao dos guararapes',
            'jaboatao dos gurarapes')
			AND state_code = 'PE'
        THEN 'jaboatao dos guararapes'

        -- =============================================
        -- BELEM DO SAO FRANCISCO - PE
        -- =============================================
        WHEN normalized_city IN (
            'belem de sao francisco',
            'belem do sao francisco')
			AND state_code = 'PE'
        THEN 'belem do sao francisco'

        -- =============================================
        -- SANTA TEREZA DO TOCANTINS - TO
        -- =============================================
        WHEN normalized_city IN (
            'santa tereza do tocantins',
            'santa terezinha do tocantins')
			AND state_code = 'TO'
        THEN 'santa tereza do tocantins'

        -- =============================================
        -- KNOWN INVALID VALUES
        -- =============================================
        WHEN normalized_city REGEXP '^[0-9]+$'
        THEN NULL
        
        WHEN normalized_city LIKE '%@%'
        THEN NULL

        WHEN TRIM(normalized_city) = ''
        THEN NULL

        -- =============================================
        -- DEFAULT
        -- =============================================
        ELSE normalized_city

    END;
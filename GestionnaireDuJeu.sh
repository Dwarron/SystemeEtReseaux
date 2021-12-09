#!/bin/bash

noMsgAvailable=true

cartesManche=()			#tableau qui represente les cartes du jeu durant une manche
nbJoueurs=0			#nombre de joueurs
nbRobots=0			#nombre de robots
nbJoueursTotal=0		#nombre de participants total
declare -i manche=0		#nombre de manche de la partie, declare en integer (afin d'utiliser +=)
etatPartie="debut"
connectPort=9091
playersPort=()
msg=""

./Server.sh $connectPort 2>/dev/null &
pidServer=$!

trap 'exitPartie; kill $$' INT

initJoueurs()
{
	#initialiser les joueurs
	read -p 'Pour commencer, selectionner le nombre de joueur(s) : ' nbJoueurs

	if [ $nbJoueurs -ge 0 ];
	then
		if [ $nbJoueurs -gt 0 ];
		then
			for i in $(eval echo {1..$nbJoueurs});
			do
				#ouvre un terminal en tache de fond pour chaque joueur
				gnome-terminal -- bash -c "./Joueurs.sh $i; bash" & #$i represente le numero du joueurs
			done
		fi
	else
		echo Nombre de joueurs errone
		initJoueurs
	fi
}

initRobots()
{
	#initialiser les robots
	echo
	read -p 'Ensuite, selectionner le nombre de robot(s) :' nbRobots

	if [ $nbRobots -ge 0 ];
	then
		if [ $nbRobots -gt 0 ];
		then
			for i in $(eval echo {1..$nbRobots});
			do
				num=$(($nbJoueurs + $i))
				#ouvre un terminal pour chaque robot mais tout est automatise
				gnome-terminal -- bash -c "./Robots.sh $num; bash" & #$num represente le numero du robot
			done
		fi
	else
		echo Nombre de robots errone
		initRobots
	fi
}

getNextMessage()
{
	nbLines=$(wc -l < tmp/socket)
	if [ $nbLines != "0" ];
	then
		noMsgAvailable=false
	fi

	while [ $noMsgAvailable = true ];
	do
		sleep 1
		nbLines=$(wc -l < tmp/socket)
		if [ $nbLines != "0" ];
		then
			noMsgAvailable=false
		fi
	done
	local line=$(awk 'NR==1 {print; exit}' tmp/socket)

	awk 'NR!=1 {print;}' tmp/socket > tmp/socketTemp
	cat tmp/socketTemp > tmp/socket
	#rm tmp/socketTemp
echo $line > tmp/socketTemp
	nbLines=$(wc -l < tmp/socket)
	if [ $nbLines = "0" ];
	then
		noMsgAvailable=true
	fi

	echo $line
}

#methode qui va melanger les cartes du jeu pour la manche
melangeCartes()
{
	#on incremente le nombre de manche a chaque distribution de cartes au joueurs
	manche+=1

	#on verifie qu'il n'y ait pas trop de cartes a distribuer
	if [ $(($manche * $nbJoueursTotal)) -gt 100 ];
	then
		echo "Pas assez de cartes pour jouer, fin de la partie."
		exitPartie
	fi

	cartes=({1..100})			#tableau qui represente les cartes du jeu au depart

	for j in $(eval echo {1..$nbJoueursTotal});
	do
		cartesString=""
		#ici la manche permet de savoir combien de cartes par joueurs on va distribuer
		for m in $(eval echo {1..$manche});
		do
			#indice aleatoire afin de recuperer une carte dans le jeu de cartes
			randomCarte=$(($RANDOM % $((99 - $cartesDistribuees))))

			#tableau qui va stocker toutes les cartes de la manche courante
			cartesManche+=(${cartes[$randomCarte]})
			cartesString+="${cartes[$randomCarte]} "
			retireCarte $randomCarte
		done

		echo "distributionCartes/${cartesString}" | nc -q 1 localhost ${playersPort[$j]}
		echo "Joueur $j a recu ses cartes"
	done
}

#methode qui retire la carte passee en parametre du tableau des cartes.
retireCarte()
{
	carteRetiree=$1		 #indice de la carte a retirer
	cartesTemp=()		 #tableau temporaire

	#on copie les cartes dans le tableau temporaire
	cartesTemp=(${cartes[*]})

	#on vide le tableau des cartes de tout son contenu avant de le remplir
	unset cartes

	#recuperation des bonnes valeurs c'est-a-dire toutes sauf la carte retiree
	for i in ${!cartesTemp[@]};
	do
		if [ $carteRetiree -neq $i ];
		then
			cartes+=(${cartesTemp[$i]})
		fi
	done
}

#methode qui envoie le top depart de la partie a tous les joueurs.
topDepart()
{
	sleep 1
	for port in ${playersPort[*]};
	do
		echo "top" | nc -q 1 localhost $port
	done

	etatPartie="jeu"
}

#methode qui permet de traiter les informations reçues par l'ensemble des joueurs.
traitementManche()
{
	carteAJouer=100		#represente la plus petite carte de la manche en cours

	#on parcourt toutes les cartes de la manche et on cherche la plus petite carte
	for i in ${cartesManche[*]};
	do
		if [ $i -lt $carteAJouer ];
		then
			carteAJouer=$i
		fi
	done

	msg=$(getNextMessage)
	local IFS='/'
	read -ra msgParts <<< $msg
	if [ "${msgParts[0]}" != "poseCarte" ];
	then
		echo "Erreur, carte a jouer attendue, obtenu :" ${msgParts[0]}
	else
		carteJouee=${msgParts[1]}
		joueur=${msgParts[2]}

		#TODO VERIF QUE LE JOUEUR A BIEN LA CARTE ET NE TRICHE PAS

		echo "Carte $carteJouee jouee par le joueur $joueur"

		for port in ${playersPort[*]};
		do
			echo "cartePosee/$carteJouee/$joueur" | nc -q 1 localhost $port
		done

		#comparaison de la carte envoyee par le joueur avec la carte a jouer
		if [ $carteJouee -eq $carteAJouer ];
		then
			#on retire la carte des cartes de la manche
			cartesManche=( ${cartesManche[*]/$carteJouee} )

			#manche finie
			if [ ${#cartesManche[@]} -eq 0 ];
			then
				etat="mancheGagnee"
				unset cartesManche
			fi;
		else
			#la carte envoyee n'etait pas la bonne donc on arrete la partie
			echo "Mauvaise carte jouee, fin de la partie"
			exitPartie
		fi
	fi
}

nouvelleManche()
{
	melangeCartes
	topDepart
}

enregistrementProcess()
{
	msg=$(getNextMessage)
	local IFS='/'
	read -ra msgParts <<< $msg
	if [ "${msgParts[0]}" != "register" ];
	then
		echo Error, not register message received ${msgParts[0]}
		kill -s INT $pidServer
		exit $!
	else
		playersPort[${msgParts[1]}]=${msgParts[2]}

		if [ ${#playersPort[@]} -eq $nbJoueursTotal ];
		then
			nouvelleManche
		fi
	fi
}

#methode qui permet de faire tourner la partie tant qu'elle n'est pas finie.
deroulementPartie()
{
	while [ $etatPartie != "fin" ]
	do
		case $etatPartie in

			"enregistrement")
				enregistrementProcess
				;;

			"jeu")
				traitementManche
				;;

			"mancheGagnee")
				for port in ${playersPort[*]};
				do
					echo "mancheGagnee" | nc -q 1 localhost $port
				done
				nouvelleManche
				;;
		esac

	done
}

#methode qui permet quand la partie est finie d'ecrire un top 10 des parties dans le gestionnaire du jeu.
#ajoute egalement la partie courante terminee a l'ensemble du fichier.
classementPartie()
{
	#on ecrit dans le fichier Classement.txt le nombre de manche et le nombre de joueur
	#l'option -e permet d'utiliser les "\t" qui represente une tabulation
	echo -e "$manche\t\t\t$nbJoueursTotaux" >> Classement.txt

	#on tri le fichier classement
	sort -n Classement.txt -o Classement.txt

	#on affiche dans le terminale du gestionnaire du jeu les titres des colonnes avec la commande "head" et le top 10 avec la commande "tail"
	echo "Voici le classement dans l'ordre croissant des partie qui on durer le plus longtemps"
	head -n 1  Classement.txt
	tail -n 10 Classement.txt
}

#fonction qui permet d'arreter la partie si une erreur a ete detectee
exitPartie()
{
	kill -s INT $pidServer

	for port in ${playersPort[*]};
	do
		echo "exitPartie" | nc -q 1 localhost $port
	done

	#comme la partie est terminee on declenche l'affichage du classement
	classementPartie
	etatPartie="fin"
}

#methode qui demarre la partie.
startPartie()
{
	etatPartie="enregistrement"
	#on initialise les joueurs de la partie
	initJoueurs
	initRobots

	nbJoueursTotal=$(($nbJoueurs + $nbRobots))
	echo "Nous avons ${nbJoueursTotaux} participants pour cette partie"

	if [ $nbJoueursTotal -lt 1 ];
	then
		echo "Pas assez de joueurs pour jouer";
		startPartie
	else
		deroulementPartie
	fi
}

#on lance la methode qui demarre la partie qui va appeler en cascade toutes les autres fonctions
startPartie

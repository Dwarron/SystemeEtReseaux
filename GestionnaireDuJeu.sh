#!/bin/bash

noMsgAvailable=true

cartesJoueurs=()
cartesManche=()			#tableau qui represente les cartes du jeu durant une manche
nbJoueurs=0			#nombre de joueurs
nbRobots=0			#nombre de robots
nbJoueursTotal=0		#nombre de participants total
declare -i manche=0		#nombre de manche de la partie, declare en integer (afin d'utiliser +=)
etatPartie="debut"
connectPort=9091
playersPort=()

./Server.sh $connectPort 2>/dev/null &
pidServer=$!

trap 'exitPartie;' INT

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
				gnome-terminal -- bash -c "./Joueurs.sh $i; echo 'Appuyez sur entrer pour quitter'; read && exit" 1>/dev/null  & #$i represente le numero du joueurs
			done
		fi
	else
		echo "Nombre de joueurs errone"
		initJoueurs
	fi
}

initRobots()
{
	#initialiser les robots
	read -p 'Ensuite, selectionner le nombre de robot(s) : ' nbRobots

	if [ $nbRobots -ge 0 ];
	then
		if [ $nbRobots -gt 0 ];
		then
			for i in $(eval echo {1..$nbRobots});
			do
				num=$(($nbJoueurs + $i))
				#ouvre un terminal pour chaque robot mais tout est automatise
				gnome-terminal -- bash -c "./Robots.sh $num; echo 'Appuyez sur entrer pour quitter'; read && exit" 1>/dev/null & #$num represente le numero du robot
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
	rm tmp/socketTemp

	nbLines=$(wc -l < tmp/socket)
	if [ $nbLines = "0" ];
	then
		noMsgAvailable=true
	fi

	echo $line
}

sendMessageToPlayer()
{
	msg=$1
	playerNb=$2
	echo $msg | nc -q 1 localhost ${playersPort[$playerNb]} 2>/dev/null

	exitCode=$?
	if [ $exitCode -ne 0 ];
	then
		sendMessageToPlayer $msg $playerNb
	fi
}

sendMessageToAllPlayer()
{
	msg=$1
	for j in ${!playersPort[@]};
	do
		sendMessageToPlayer $msg $j
	done
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
			randomCarte=$(($RANDOM % $((99 - ${#cartesManche[@]}))))

			#tableau qui va stocker toutes les cartes de la manche courante
			cartesManche+=(${cartes[$randomCarte]})
			cartesJoueurs+=(${cartes[$randomCarte]})
			cartesString+="${cartes[$randomCarte]} "
			retireCarte $randomCarte

		done

		sendMessageToPlayer "distributionCartes/${cartesString}" $j
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
		if [ $carteRetiree -ne $i ];
		then
			cartes+=(${cartesTemp[$i]})
		fi
	done
}

#methode qui retire la carte passee en parametre du tableau des cartes de la manche.
retireCarteManche()
{
	carteRetiree=$1		 #carte a retirer
	temp=()		 #tableau temporaire

	#on copie les cartes dans le tableau temporaire
	temp=(${cartesManche[*]})

	#on vide le tableau des cartes de tout son contenu avant de le remplir
	unset cartesManche

	#recuperation des bonnes valeurs c'est-a-dire toutes sauf la carte retiree
	for i in ${temp[*]};
	do
		if [ $carteRetiree -ne $i ];
		then
			cartesManche+=($i)
		fi
	done
}

#methode qui envoie le top depart de la partie a tous les joueurs.
topDepart()
{
	sleep $(($RANDOM % 6))
	sendMessageToAllPlayer "top"

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
	oldIFS=$IFS
	local IFS='/'
	read -ra msgParts <<< $msg
	IFS=$oldIFS
	if [ "${msgParts[0]}" != "poseCarte" ];
	then
		echo "Erreur, carte a jouer attendue, obtenu :" ${msgParts[0]}
	else
		carteJouee=${msgParts[1]}
		joueur=${msgParts[2]}

		#verification que le joueur possede bien cette carte et ne triche pas
		local exist=false
		for i in ${cartesManche[*]};
		do
			if [ $carteJouee -eq $i ];
			then
				exist=true
			fi
		done

		local possedee=false
		if [ $exist = true ];
		then
			for i in ${!cartesJoueurs[@]};
			do
				if [ $carteJouee -eq ${cartesJoueurs[$i]} ];
				then
					#intervalle dans lesquelles sont comprises les cartes du joueur qui a joue (pour verifier qu'il possede bien la carte)
					debutCartesJoueur=$((($joueur - 1) * $manche))		#inclu
					finCartesJoueur=$(($debutCartesJoueur + $manche))		#exclu
					if [ $i -ge $debutCartesJoueur -a $i -lt $finCartesJoueur ];
					then
						possedee=true
					fi
				fi
			done
		fi

		if [ $possedee = true ];
		then
			echo "Carte $carteJouee jouee par le joueur $joueur"
			sendMessageToAllPlayer "cartePosee/${carteJouee}/${joueur}"

			#comparaison de la carte envoyee par le joueur avec la carte a jouer
			if [ $carteJouee -eq $carteAJouer ];
			then
				#on retire la carte des cartes de la manche
				retireCarteManche $carteJouee
				echo "Il reste ${#cartesManche[@]} cartes"

				#manche finie
				if [ ${#cartesManche[@]} -eq 0 ];
				then
					echo "Manche gagnee"
					echo
					etatPartie="mancheGagnee"
					unset cartesManche
					unset cartesJoueurs
				fi;
			else
				#la carte envoyee n'etait pas la bonne donc on arrete la partie
				echo "Mauvaise carte jouee, fin de la partie"
				sendMessageToAllPlayer "mauvaiseCarte"
				exitPartie
			fi
		else
			echo "Tentative de triche"
			sendMessageToAllPlayer "triche"
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
	oldIFS=$IFS
	local IFS='/'
	read -ra msgParts <<< $msg
	IFS=$oldIFS
	if [ "${msgParts[0]}" != "register" ];
	then
		echo "Error, not register message received" ${msgParts[0]}
	else
		playersPort[${msgParts[1]}]=${msgParts[2]}

		if [ ${#playersPort[@]} -eq $nbJoueursTotal ];
		then
			sleep 1
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
				sendMessageToAllPlayer "mancheGagnee"
				nouvelleManche
				;;
		esac

	done
}

#methode qui permet quand la partie est finie d'ecrire un top 10 des parties dans le gestionnaire du jeu.
#ajoute egalement la partie courante terminee a l'ensemble du fichier.
classementPartie()
{
	echo
	#on ecrit dans le fichier Classement.txt le nombre de manche et le nombre de joueur
	#l'option -e permet d'utiliser les "\t" qui represente une tabulation
	echo -e "$manche\t\t\t$nbJoueursTotal" >> Classement.txt

	#on tri le fichier classement
	sort -n Classement.txt -o Classement.txt

	#on affiche dans le terminale du gestionnaire du jeu les titres des colonnes avec la commande "head" et le top 10 avec la commande "tail"
	echo "Voici le classement dans l'ordre croissant des parties qui ont durees le plus longtemps"
	echo -e "Manche\t\t\tNombre de joueurs"
	head -n 1  Classement.txt
	tail -n 10 Classement.txt
}

#fonction qui permet d'arreter la partie si une erreur a ete detectee
exitPartie()
{
	kill -s INT $pidServer
	etatPartie="fin"

	sendMessageToAllPlayer "exitPartie"

	#comme la partie est terminee on declenche l'affichage du classement
	classementPartie
}

#methode qui demarre la partie.
startPartie()
{
	etatPartie="enregistrement"
	#on initialise les joueurs de la partie
	initJoueurs
	initRobots

	nbJoueursTotal=$(($nbJoueurs + $nbRobots))
	echo "Nous avons ${nbJoueursTotal} participants pour cette partie"

	if [ $nbJoueursTotal -lt 2 ];
	then
		echo "Pas assez de joueurs pour jouer";
		startPartie
	else
		deroulementPartie
	fi
}

#on lance la methode qui demarre la partie qui va appeler en cascade toutes les autres fonctions
startPartie
